import 'dart:async';

import 'package:flutter/foundation.dart';

import 'foundation_client.dart';

/// Page-owned subscriptions, never a core/database/network-session owner.
final class FoundationController extends ChangeNotifier {
  FoundationController(this._client);
  final FoundationClient _client;
  CatalogSnapshot? _snapshot;
  CatalogGame? _selected;
  ResumeCapability _resume = const ResumeCapability(ResumeState.querying);
  bool _loading = false;
  bool _launching = false;
  bool _disposed = false;
  String? _error;
  int _catalogRequest = 0;
  int _selectionRequest = 0;

  CatalogSnapshot? get snapshot => _snapshot;
  CatalogGame? get selected => _selected;
  ResumeCapability get resume => _resume;
  bool get loading => _loading;
  bool get launching => _launching;
  String? get error => _error;

  Future<void> refresh() async {
    if (_disposed) return;
    final request = ++_catalogRequest;
    ++_selectionRequest;
    _loading = true;
    _error = null;
    _resume = const ResumeCapability(ResumeState.querying);
    notifyListeners();
    try {
      final next = await _client.catalogSnapshot();
      if (_disposed || request != _catalogRequest) return;
      if (_snapshot == null || next.generation >= _snapshot!.generation) {
        _snapshot = next;
      }
      final games = _snapshot!.games;
      final id = _selected?.canonicalId;
      _selected = games.where((game) => game.canonicalId == id).firstOrNull;
      _selected ??= games.firstOrNull;
      _loading = false;
      _queryResume();
    } catch (_) {
      if (_disposed || request != _catalogRequest) return;
      _loading = false;
      _error = '游戏库暂时不可用';
      _resume = const ResumeCapability(ResumeState.unavailable);
      notifyListeners();
    }
  }

  void select(String canonicalId) {
    if (_disposed || _launching || _loading) return;
    final game = _snapshot?.games
        .where((item) => item.canonicalId == canonicalId)
        .firstOrNull;
    if (game == null || game.canonicalId == _selected?.canonicalId) return;
    _selected = game;
    _error = null;
    _queryResume();
  }

  void _queryResume() {
    final request = ++_selectionRequest;
    final game = _selected;
    _resume = game != null && game.available
        ? const ResumeCapability(ResumeState.querying)
        : ResumeCapability(
            ResumeState.unavailable,
            reason: game?.unavailableReason ?? '',
          );
    notifyListeners();
    if (game == null || !game.available) return;
    unawaited(_resolveResume(game.canonicalId, request));
  }

  Future<void> _resolveResume(String id, int request) async {
    ResumeCapability capability;
    try {
      capability = await _client.resumeCapability(id);
    } catch (_) {
      capability = const ResumeCapability(
        ResumeState.unavailable,
        reason: '暂时无法读取进度',
      );
    }
    if (_disposed || request != _selectionRequest) return;
    _resume = capability;
    notifyListeners();
  }

  Future<void> launch() async {
    final game = _selected;
    if (_disposed ||
        _loading ||
        _launching ||
        game == null ||
        !game.available ||
        (_resume.state != ResumeState.available &&
            _resume.state != ResumeState.none)) {
      return;
    }
    _launching = true;
    _error = null;
    notifyListeners();
    String? failure;
    try {
      final result = await _client.launch(game.canonicalId);
      if (result.status == LaunchStatus.unavailable) {
        failure = result.reason.isNotEmpty ? result.reason : '当前无法启动游戏';
      }
    } catch (_) {
      failure = '当前无法启动游戏';
    }
    if (_disposed) return;
    _launching = false;
    await refresh();
    if (_disposed) return;
    if (failure != null) _error = failure;
    notifyListeners();
  }

  Future<void> openNative(String page) async {
    if (_disposed || _launching) return;
    _launching = true;
    notifyListeners();
    String? failure;
    try {
      await _client.openNative(page);
    } catch (_) {
      failure = '暂时无法打开页面';
    }
    if (_disposed) return;
    _launching = false;
    await refresh();
    if (_disposed) return;
    if (failure != null) _error = failure;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_catalogRequest;
    ++_selectionRequest;
    super.dispose();
  }
}
