import 'package:flutter/services.dart';

/// G1 projections only. Native owners retain catalog, storage and sessions.
final class CatalogGame {
  const CatalogGame({
    required this.canonicalId,
    required this.titleEn,
    required this.titleZhHans,
    this.available = true,
    this.unavailableReason = '',
  });

  final String canonicalId;
  final String titleEn;
  final String titleZhHans;
  final bool available;
  final String unavailableReason;

  String title(bool chinese) {
    final primary = chinese ? titleZhHans : titleEn;
    final secondary = chinese ? titleEn : titleZhHans;
    return primary.isNotEmpty
        ? primary
        : secondary.isNotEmpty
        ? secondary
        : canonicalId;
  }
}

final class CatalogSnapshot {
  CatalogSnapshot({required this.generation, required List<CatalogGame> games})
    : games = List.unmodifiable(games);

  final int generation;
  final List<CatalogGame> games;
}

enum ResumeState { querying, available, none, unavailable }

final class ResumeCapability {
  const ResumeCapability(this.state, {this.reason = ''});
  final ResumeState state;
  final String reason;
}

enum LaunchStatus { returned, cancelled, unavailable }

final class LaunchResult {
  const LaunchResult(this.status, {this.reason = ''});
  final LaunchStatus status;
  final String reason;
}

abstract interface class FoundationClient {
  Future<CatalogSnapshot> catalogSnapshot();
  Future<ResumeCapability> resumeCapability(String canonicalId);

  /// Completes when the native route returns, cancels or fails to open.
  Future<LaunchResult> launch(String canonicalId);
  Future<void> openNative(String page);
}

/// Experimental host bridge. No SQLite, ROM bytes or video/PCM cross this API.
final class ChannelFoundationClient implements FoundationClient {
  const ChannelFoundationClient({
    MethodChannel channel = const MethodChannel('flynes/foundation'),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<CatalogSnapshot> catalogSnapshot() async {
    final data = _map(await _channel.invokeMethod<Object?>('catalogSnapshot'));
    final generation = data['generation'];
    final rows = data['games'];
    if (generation is! int || generation < 0 || rows is! List) {
      throw const FormatException('Invalid catalog snapshot');
    }
    final ids = <String>{};
    final games = <CatalogGame>[];
    for (final row in rows) {
      final item = _map(row);
      final id = _text(item, 'canonicalId');
      final available = item['available'];
      if (id.isEmpty || !ids.add(id) || available is! bool) {
        throw const FormatException('Invalid catalog identity or availability');
      }
      games.add(
        CatalogGame(
          canonicalId: id,
          titleEn: _text(item, 'titleEn'),
          titleZhHans: _text(item, 'titleZhHans'),
          available: available,
          unavailableReason: _text(item, 'unavailableReason', optional: true),
        ),
      );
    }
    return CatalogSnapshot(generation: generation, games: games);
  }

  @override
  Future<ResumeCapability> resumeCapability(String canonicalId) async {
    final data = _map(
      await _channel.invokeMethod<Object?>('resumeCapability', {
        'canonicalId': canonicalId,
      }),
    );
    final state = switch (data['state']) {
      'available' => ResumeState.available,
      'none' => ResumeState.none,
      'unavailable' => ResumeState.unavailable,
      _ => throw const FormatException('Invalid resume capability'),
    };
    return ResumeCapability(
      state,
      reason: _text(data, 'reason', optional: true),
    );
  }

  @override
  Future<LaunchResult> launch(String canonicalId) async {
    final data = _map(
      await _channel.invokeMethod<Object?>('launch', {
        'canonicalId': canonicalId,
      }),
    );
    final status = switch (data['status']) {
      'returned' => LaunchStatus.returned,
      'cancelled' => LaunchStatus.cancelled,
      'unavailable' => LaunchStatus.unavailable,
      _ => throw const FormatException('Invalid launch result'),
    };
    return LaunchResult(status, reason: _text(data, 'reason', optional: true));
  }

  @override
  Future<void> openNative(String page) async {
    if (!const {'settings', 'sources', 'nearby'}.contains(page)) {
      throw ArgumentError.value(page, 'page');
    }
    await _channel.invokeMethod<void>('openNative', {'page': page});
  }

  static Map<Object?, Object?> _map(Object? value) {
    if (value is! Map) {
      throw const FormatException('Expected native projection');
    }
    return Map<Object?, Object?>.from(value);
  }

  static String _text(
    Map<Object?, Object?> value,
    String key, {
    bool optional = false,
  }) {
    final field = value[key];
    if (optional && field == null) return '';
    if (field is! String) throw FormatException('Invalid $key');
    return field;
  }
}
