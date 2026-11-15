import 'dart:async';

import 'package:bird_audio/bird_audio.dart';
import 'package:ecoyard/features/plan/plan_controller.dart';
import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

/// A store that wraps another and lets a test hold or break single calls.
class SpyStore implements PlanStore {
  SpyStore([PlanStore? inner]) : inner = inner ?? InMemoryPlanStore();
  final PlanStore inner;
  int closes = 0;
  int adds = 0;
  bool failLoad = false;
  Completer<void>? holdAdd;

  @override
  Future<List<PlanEntry>> load() async {
    if (failLoad) throw StateError('load failed');
    return inner.load();
  }

  @override
  Future<PlanAddResult> add({
    required String birdId,
    required List<PlanCandidate> actions,
    required DateTime now,
  }) async {
    adds++;
    await holdAdd?.future;
    return inner.add(birdId: birdId, actions: actions, now: now);
  }

  @override
  Future<void> setDone(
    String actionId, {
    required bool done,
    required DateTime now,
  }) => inner.setDone(actionId, done: done, now: now);

  @override
  Future<void> remove(String actionId) => inner.remove(actionId);

  @override
  Future<void> clear() => inner.clear();

  @override
  Future<void> close() async => closes++;
}

void main() {
  final repo = realAppContent().repo;
  final cardinal = repo.birdById('norcar')!;
  final goldfinch = repo.birdById('amegfi')!;
  PlanCandidate cand(String id) =>
      PlanCandidate.fromAction(repo.actionById(id)!);

  PlanController make(Future<PlanStore> Function() open) =>
      PlanController(repo: repo, openStore: open, now: fixedNow);

  test('init opens the store and shows an empty, ready plan', () async {
    final c = make(() async => SpyStore());
    await c.init();
    expect(c.state, PlanLoadState.ready);
    expect(c.view!.items, isEmpty);
  });

  test(
    'a failed open is "failed", never an empty plan; retry recovers',
    () async {
      var n = 0;
      final c = make(() async {
        if (++n == 1) throw StateError('locked');
        return SpyStore();
      });
      await c.init();
      expect(c.state, PlanLoadState.failed);
      expect(c.view, isNull);
      await c.init();
      expect(c.state, PlanLoadState.ready);
    },
  );

  test('two init calls at once open the database once', () async {
    var opens = 0;
    final gate = Completer<PlanStore>();
    final c = make(() {
      opens++;
      return gate.future;
    });
    final a = c.init();
    final b = c.init();
    gate.complete(SpyStore());
    await Future.wait([a, b]);
    expect(opens, 1);
    expect(c.state, PlanLoadState.ready);
  });

  test('add before the store has opened waits for it and succeeds', () async {
    final gate = Completer<PlanStore>();
    var opens = 0;
    final c = make(() {
      opens++;
      return gate.future;
    });
    unawaited(c.init());
    final f = c.add(bird: cardinal, actions: [cand('add-water-source')]);
    gate.complete(SpyStore());
    final r = await f;
    expect(r.added, ['add-water-source']);
    expect(opens, 1);
  });

  test('add retries opening a store that failed earlier', () async {
    var n = 0;
    final c = make(() async {
      if (++n == 1) throw StateError('locked');
      return SpyStore();
    });
    await c.init();
    expect(c.state, PlanLoadState.failed);
    final r = await c.add(bird: cardinal, actions: [cand('add-water-source')]);
    expect(r.added, hasLength(1));
    expect(c.state, PlanLoadState.ready);
    expect(n, 2);
  });

  test(
    'add throws when the store can never open, and sets no banner',
    () async {
      final c = make(() async => throw StateError('gone'));
      await expectLater(
        c.add(bird: cardinal, actions: [cand('add-water-source')]),
        throwsA(anything),
      );
      expect(c.banner, isNull);
    },
  );

  test(
    'add that saved but could not re-read still returns, plan shows failed',
    () async {
      final store = SpyStore();
      final c = make(() async => store);
      await c.init();
      store.failLoad = true;
      final r = await c.add(
        bird: cardinal,
        actions: [cand('add-water-source')],
      );
      expect(r.added, ['add-water-source']);
      expect(c.state, PlanLoadState.failed);
      store.failLoad = false;
      await c.init();
      expect(c.view!.items, hasLength(1));
    },
  );

  group('banner wording', () {
    Future<String> bannerAfter(List<String> first, List<String> second) async {
      final c = make(() async => SpyStore());
      await c.init();
      if (first.isNotEmpty) {
        await c.add(bird: goldfinch, actions: first.map(cand).toList());
      }
      await c.add(bird: cardinal, actions: second.map(cand).toList());
      return c.banner!;
    }

    test('one new action', () async {
      expect(
        await bannerAfter([], ['add-water-source']),
        '1 action added for Northern Cardinal',
      );
    });
    test('several new actions', () async {
      expect(
        await bannerAfter([], ['add-water-source', 'plant-native-shrub']),
        '2 actions added for Northern Cardinal',
      );
    });
    test('new and already there', () async {
      expect(
        await bannerAfter(
          ['add-water-source'],
          ['add-water-source', 'plant-native-shrub'],
        ),
        '1 action added for Northern Cardinal · 1 already in your plan',
      );
    });
    test('only one action, already there', () async {
      expect(
        await bannerAfter(['add-water-source'], ['add-water-source']),
        'That action was already in your plan. '
        'Northern Cardinal was added to it.',
      );
    });
    test('several actions, all already there', () async {
      expect(
        await bannerAfter(
          ['add-water-source', 'plant-native-shrub'],
          ['add-water-source', 'plant-native-shrub'],
        ),
        'Those actions were already in your plan. '
        'Northern Cardinal was added to them.',
      );
    });
  });

  test('ticking clears the banner; dismiss clears it too', () async {
    final c = make(() async => SpyStore());
    await c.init();
    await c.add(bird: cardinal, actions: [cand('add-water-source')]);
    expect(c.banner, isNotNull);
    c.dismissBanner();
    expect(c.banner, isNull);
    await c.add(bird: cardinal, actions: [cand('plant-native-shrub')]);
    expect(c.banner, isNotNull);
    await c.setDone('plant-native-shrub', true);
    expect(c.banner, isNull);
    expect(c.view!.progress.done, 1);
  });

  test('a failed tick sets an error; the next success clears it', () async {
    final store = InMemoryPlanStore();
    final c = make(() async => store);
    await c.init();
    await c.add(bird: cardinal, actions: [cand('add-water-source')]);
    store.failNext = StateError('x');
    await c.setDone('add-water-source', true);
    expect(c.actionError, isNotNull);
    expect(c.view!.progress.done, 0);
    await c.setDone('add-water-source', true);
    expect(c.actionError, isNull);
    expect(c.view!.progress.done, 1);
  });

  test(
    'ticking while the store never opened reports an error, no crash',
    () async {
      final c = make(() async => throw StateError('gone'));
      await c.init();
      await c.setDone('add-water-source', true);
      expect(c.actionError, isNotNull);
      expect(c.state, PlanLoadState.failed);
    },
  );

  test('remove drops the item and updates the progress', () async {
    final c = make(() async => SpyStore());
    await c.init();
    await c.add(
      bird: cardinal,
      actions: [cand('add-water-source'), cand('plant-native-shrub')],
    );
    await c.remove('add-water-source');
    expect(c.view!.items.map((i) => i.entry.actionId), ['plant-native-shrub']);
    expect(c.view!.progress.total, 1);
  });

  group('dispose', () {
    test(
      'while the database is still opening: it is closed, nothing throws',
      () async {
        final gate = Completer<PlanStore>();
        final store = SpyStore();
        final c = make(() => gate.future);
        final f = c.init();
        c.dispose();
        gate.complete(store);
        await f;
        await Future<void>.delayed(Duration.zero);
        expect(store.closes, 1);
      },
    );

    test(
      'during a save: the save finishes first, then the store closes',
      () async {
        final store = SpyStore()..holdAdd = Completer<void>();
        final c = make(() async => store);
        await c.init();
        final f = c.add(bird: cardinal, actions: [cand('add-water-source')]);
        await Future<void>.delayed(Duration.zero);
        c.dispose();
        await Future<void>.delayed(Duration.zero);
        expect(store.closes, 0, reason: 'a save is still running');
        store.holdAdd!.complete();
        await f;
        await Future<void>.delayed(Duration.zero);
        expect(store.closes, 1);
        expect((await store.inner.load()), hasLength(1));
      },
    );

    test('with nothing running it closes at once', () async {
      final store = SpyStore();
      final c = make(() async => store);
      await c.init();
      c.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(store.closes, 1);
    });
  });
}
