import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flynes_ui/native_client/foundation_client.dart';
import 'package:flynes_ui/native_client/foundation_controller.dart';

const a = CatalogGame(canonicalId: 'a', titleEn: 'Alpha', titleZhHans: '甲');
const b = CatalogGame(canonicalId: 'b', titleEn: 'Beta', titleZhHans: '乙');

class FakeClient implements FoundationClient {
  CatalogSnapshot snapshot = CatalogSnapshot(generation: 1, games: [a, b]);
  final queries = <String, List<Completer<ResumeCapability>>>{};
  final launchDone = Completer<LaunchResult>();
  int launches = 0;
  int snapshots = 0;

  @override
  Future<CatalogSnapshot> catalogSnapshot() async {
    snapshots++;
    return snapshot;
  }

  @override
  Future<ResumeCapability> resumeCapability(String canonicalId) {
    final result = Completer<ResumeCapability>();
    (queries[canonicalId] ??= []).add(result);
    return result.future;
  }

  @override
  Future<LaunchResult> launch(String canonicalId) {
    launches++;
    return launchDone.future;
  }

  @override
  Future<void> openNative(String page) async {}
}

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'first selection is available without reordering or overriding later choice',
    () async {
      const missing = CatalogGame(
        canonicalId: 'missing',
        titleEn: 'Missing',
        titleZhHans: '',
        available: false,
      );
      final client = FakeClient()
        ..snapshot = CatalogSnapshot(generation: 1, games: [missing, a, b]);
      final state = FoundationController(client);
      await state.refresh();
      expect(state.selected, a);
      expect(state.snapshot!.games, [missing, a, b]);
      state.select('missing');
      await state.refresh();
      expect(state.selected, missing);
      expect(state.resume.state, ResumeState.unavailable);
      state.dispose();
    },
  );

  test('snapshot owns an immutable copy', () {
    final games = [a];
    final snapshot = CatalogSnapshot(generation: 1, games: games);
    games.clear();
    expect(snapshot.games, [a]);
    expect(() => snapshot.games.clear(), throwsUnsupportedError);
  });

  test('late resume result never overwrites a new selection', () async {
    final client = FakeClient();
    final state = FoundationController(client);
    await state.refresh();
    state.select('b');
    client.queries['b']!.single.complete(
      const ResumeCapability(ResumeState.none),
    );
    await flush();
    client.queries['a']!.single.complete(
      const ResumeCapability(ResumeState.available),
    );
    await flush();
    expect(state.selected?.canonicalId, 'b');
    expect(state.resume.state, ResumeState.none);
    expect(client.launches, 0);
    state.dispose();
  });

  test('same ID after refresh still rejects the older capability', () async {
    final client = FakeClient();
    final state = FoundationController(client);
    await state.refresh();
    await state.refresh();
    client.queries['a']!.last.complete(
      const ResumeCapability(ResumeState.none),
    );
    await flush();
    client.queries['a']!.first.complete(
      const ResumeCapability(ResumeState.available),
    );
    await flush();
    expect(state.resume.state, ResumeState.none);
    state.dispose();
  });

  test('launch is serialized and return refreshes true capability', () async {
    final client = FakeClient();
    final state = FoundationController(client);
    await state.refresh();
    client.queries['a']!.single.complete(
      const ResumeCapability(ResumeState.none),
    );
    await flush();
    final launched = state.launch();
    await state.launch();
    expect(client.launches, 1);
    expect(state.launching, isTrue);
    client.launchDone.complete(const LaunchResult(LaunchStatus.returned));
    await launched;
    expect(client.snapshots, 2);
    expect(state.resume.state, ResumeState.querying);
    state.dispose();
  });

  test('unavailable source never queries progress or launches', () async {
    final client = FakeClient()
      ..snapshot = CatalogSnapshot(
        generation: 1,
        games: [
          const CatalogGame(
            canonicalId: 'gone',
            titleEn: 'Gone',
            titleZhHans: '',
            available: false,
            unavailableReason: '来源不可用',
          ),
        ],
      );
    final state = FoundationController(client);
    await state.refresh();
    await state.launch();
    expect(state.resume.state, ResumeState.unavailable);
    expect(client.queries, isEmpty);
    expect(client.launches, 0);
    state.dispose();
  });

  test('disposing a page only detaches notifications from late work', () async {
    final client = FakeClient();
    final state = FoundationController(client);
    await state.refresh();
    int updates = 0;
    state.addListener(() => updates++);
    state.dispose();
    client.queries['a']!.single.complete(
      const ResumeCapability(ResumeState.available),
    );
    await flush();
    expect(updates, 0);
  });

  test('lower snapshot generation cannot replace newer native state', () async {
    final client = FakeClient()
      ..snapshot = CatalogSnapshot(generation: 4, games: [a]);
    final state = FoundationController(client);
    await state.refresh();
    client.snapshot = CatalogSnapshot(generation: 3, games: [b]);
    await state.refresh();
    expect(state.snapshot?.generation, 4);
    expect(state.selected?.canonicalId, 'a');
    state.dispose();
  });
}
