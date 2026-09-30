import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../native_client/product_client.dart';

/// View state only. Catalog facts and filtering belong to the native product owner.
class ProductController extends ChangeNotifier {
  ProductController(this.client);
  final ProductClient client;
  ProductMap bootstrapData = {};
  ProductMap settings = {};
  ProductMap? selected;
  String category = 'all';
  String query = '';
  bool multiplayerOnly = false;
  String selectedId = '';
  String resumeState = 'querying';
  String error = '';
  bool loading = false;
  bool busy = false;
  int total = 0;
  int catalogGeneration = 0;
  int viewRevision = 0;
  final Map<int, List<ProductMap>> windows = {};
  final Map<String, String> selections = {};
  int _catalogRequest = 0;
  int _selectionRequest = 0;
  int _initializationRequest = 0;
  bool _disposed = false;
  Timer? _searchTimer;
  String get locale =>
      (settings['localeTag'] ??
              bootstrapData['localePreference'] ??
              bootstrapData['locale'] ??
              'system')
          as String;
  String get purpose =>
      (bootstrapData['context'] is Map
              ? (bootstrapData['context'] as Map)['purpose']
              : null)
          as String? ??
      'single';

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  String _code(Object error) =>
      error is ProductFailure ? error.code : 'service_unavailable';
  bool _current(int request) => !_disposed && request == _catalogRequest;
  List<ProductMap> _items(ProductMap result) {
    final rows = result['items'];
    if (rows is! List || rows.length > 128) {
      throw const ProductFailure('invalid_response');
    }
    final ids = <String>{};
    return List.unmodifiable(
      rows.map((row) {
        if (row is! Map ||
            row['canonicalId'] is! String ||
            (row['canonicalId'] as String).isEmpty ||
            !ids.add(row['canonicalId'] as String)) {
          throw const ProductFailure('invalid_response');
        }
        return Map<String, Object?>.unmodifiable(
          Map<String, Object?>.from(row),
        );
      }),
    );
  }

  Future<void> initialize() async {
    final request = ++_initializationRequest;
    ++_catalogRequest;
    ++_selectionRequest;
    loading = true;
    error = '';
    _changed();
    try {
      final data = await client.bootstrap();
      if (_disposed || request != _initializationRequest) return;
      bootstrapData = data;
      final preferences = data['preferences'];
      if (preferences is Map) {
        final savedCategory = preferences['category'];
        if (const [
          'recent',
          'favorites',
          'all',
          'builtin',
        ].contains(savedCategory)) {
          category = savedCategory as String;
        }
        multiplayerOnly = preferences['multiplayerOnly'] == true;
        if (preferences['selections'] is Map) {
          for (final entry in (preferences['selections'] as Map).entries) {
            if (entry.key is String && entry.value is String) {
              selections[entry.key as String] = entry.value as String;
            }
          }
        }
        selectedId = selections[category] ?? '';
      }
      await refresh();
    } catch (failure) {
      if (!_disposed && request == _initializationRequest) {
        error = _code(failure);
      }
    } finally {
      if (!_disposed && request == _initializationRequest) {
        loading = false;
        _changed();
      }
    }
  }

  /// A host lease changes UI observation only; native sessions keep running.
  void adoptHost(ProductMap data) {
    ++_initializationRequest;
    ++_catalogRequest;
    ++_selectionRequest;
    _searchTimer?.cancel();
    bootstrapData = data;
    busy = false;
    loading = false;
    error = '';
    _changed();
  }

  Future<void> refresh() async {
    final request = ++_catalogRequest;
    final selectionRequest = ++_selectionRequest;
    loading = true;
    error = '';
    _changed();
    try {
      final result = await client.call('catalogQuery', {
        'category': category,
        'query': query,
        'multiplayerOnly': multiplayerOnly,
        'selectedId': selectedId,
        'locale': locale,
      });
      if (!_current(request)) return;
      final items = _items(result);
      catalogGeneration = result['catalogGeneration'] as int;
      viewRevision = result['viewRevision'] as int;
      total = result['total'] as int;
      windows.clear();
      windows[0] = items;
      if (selectionRequest == _selectionRequest) {
        selectedId = result['selectedId'] as String;
        selections[category] = selectedId;
        if (selectedId.isNotEmpty) {
          await choose(selectedId, persistSelection: false);
        } else {
          selected = null;
          resumeState = 'none';
        }
      }
    } catch (failure) {
      if (_current(request)) error = _code(failure);
    } finally {
      if (_current(request)) {
        loading = false;
        _changed();
      }
    }
  }

  Future<void> retry() => bootstrapData.isEmpty ? initialize() : refresh();

  Future<void> choose(String id, {bool persistSelection = true}) async {
    final request = ++_selectionRequest;
    selectedId = id;
    selections[category] = id;
    // Navigation intent is independent of asynchronous detail/head observation.
    if (persistSelection) unawaited(saveNavigation());
    selected = null;
    error = '';
    resumeState = 'querying';
    _changed();
    try {
      final item = await client.call('catalogItem', {'canonicalId': id});
      if (_disposed || request != _selectionRequest) return;
      selected = item;
      _changed();
      if (purpose == 'nearby') {
        resumeState = 'none';
        _changed();
        return;
      }
      final result = await client.call('resumeCapability', {'canonicalId': id});
      if (_disposed || request != _selectionRequest) return;
      resumeState = result['state'] as String;
      if (resumeState == 'unavailable') {
        error = result['reason'] as String? ?? 'history_unavailable';
      }
    } catch (failure) {
      if (!_disposed && request == _selectionRequest) {
        resumeState = 'unavailable';
        error = _code(failure);
      }
    }
    if (!_disposed && request == _selectionRequest) _changed();
  }

  Future<void> favorite(bool value) async {
    if (busy || selectedId.isEmpty) return;
    busy = true;
    error = '';
    final id = selectedId;
    final selectionRequest = _selectionRequest;
    final catalogRequest = _catalogRequest;
    _changed();
    try {
      final result = await client.call('setFavorite', {
        'canonicalId': id,
        'value': value,
      });
      if (_disposed) return;
      if (selectionRequest == _selectionRequest &&
          catalogRequest == _catalogRequest &&
          selectedId == id &&
          selected != null) {
        selected = {...selected!, 'favorite': result['favorite']};
      }
      // The mutation committed even if navigation changed while it was pending.
      // Query the current view and selection instead of retaining stale windows.
      await refresh();
    } catch (failure) {
      if (!_disposed &&
          selectionRequest == _selectionRequest &&
          catalogRequest == _catalogRequest) {
        error = _code(failure);
      }
    } finally {
      busy = false;
      _changed();
    }
  }

  Future<void> launch() async {
    if (busy ||
        selectedId.isEmpty ||
        selected?['canonicalId'] != selectedId ||
        resumeState == 'querying' ||
        resumeState == 'unavailable') {
      return;
    }
    busy = true;
    error = '';
    final selectionRequest = _selectionRequest;
    final catalogRequest = _catalogRequest;
    _changed();
    try {
      final result = await client.call('launch', {
        'canonicalId': selectedId,
        'purpose': purpose,
      });
      if (_disposed ||
          selectionRequest != _selectionRequest ||
          catalogRequest != _catalogRequest) {
        return;
      }
      if (result['status'] == 'unavailable') {
        error = result['reason'] as String? ?? 'launch_failed';
      } else {
        await refresh();
      }
    } catch (failure) {
      if (!_disposed &&
          selectionRequest == _selectionRequest &&
          catalogRequest == _catalogRequest) {
        error = _code(failure);
      }
    } finally {
      busy = false;
      _changed();
    }
  }

  Future<void> loadWindow(int offset) async {
    final request = _catalogRequest;
    final generation = catalogGeneration;
    final revision = viewRevision;
    try {
      final result = await client.call('catalogWindow', {
        'catalogGeneration': catalogGeneration,
        'viewRevision': viewRevision,
        'offset': offset,
        'limit': 128,
      });
      if (!_current(request) ||
          catalogGeneration != generation ||
          viewRevision != revision) {
        return;
      }
      if (result['catalogGeneration'] != generation ||
          result['viewRevision'] != revision) {
        throw const ProductFailure('snapshot_expired');
      }
      windows.remove(offset);
      windows[offset] = _items(result);
      while (windows.length > 3) {
        windows.remove(windows.keys.first);
      }
    } catch (failure) {
      if (_current(request) &&
          catalogGeneration == generation &&
          viewRevision == revision) {
        if (_code(failure) == 'snapshot_expired') {
          await refresh();
        } else {
          error = _code(failure);
        }
      }
    }
    _changed();
  }

  void search(String value, {bool immediate = false}) {
    query = value;
    _searchTimer?.cancel();
    ++_catalogRequest; // Invalidate in-flight results before debounce elapses.
    ++_selectionRequest;
    if (immediate) {
      unawaited(refresh());
    } else {
      _searchTimer = Timer(const Duration(milliseconds: 150), refresh);
    }
    _changed();
  }

  Future<void> changeCategory(String value) async {
    if (!const ['recent', 'favorites', 'all', 'builtin'].contains(value)) {
      return;
    }
    _searchTimer?.cancel();
    category = value;
    selectedId = selections[value] ?? '';
    selected = null;
    resumeState = 'querying';
    await refresh();
    await saveNavigation();
  }

  Future<void> toggleMultiplayer() async {
    multiplayerOnly = !multiplayerOnly;
    _searchTimer?.cancel();
    await refresh();
    await saveNavigation();
  }

  Future<void> saveNavigation() async {
    final selectionRequest = _selectionRequest;
    final catalogRequest = _catalogRequest;
    try {
      await client.call('saveNavigation', {
        'category': category,
        'multiplayerOnly': multiplayerOnly,
        'selections': Map<String, String>.from(selections),
      });
    } catch (failure) {
      if (!_disposed &&
          selectionRequest == _selectionRequest &&
          catalogRequest == _catalogRequest) {
        error = _code(failure);
        _changed();
      }
    }
  }

  ProductMap? itemAt(int index) {
    for (final entry in windows.entries) {
      if (index >= entry.key && index < entry.key + entry.value.length) {
        return entry.value[index - entry.key];
      }
    }
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    _searchTimer?.cancel();
    client.dispose();
    super.dispose();
  }
}
