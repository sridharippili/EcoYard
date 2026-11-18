import 'package:bird_audio/bird_audio.dart';
import 'package:ecoyard/features/plan/plan_controller.dart';
import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  group('otherBirdId', () {
    test('a stable lowercase slug from the name', () {
      expect(
        PlanController.otherBirdId('Laughing Kookaburra'),
        'other-laughing-kookaburra',
      );
      expect(
        PlanController.otherBirdId("  Wilson's  Snipe!! "),
        'other-wilson-s-snipe',
      );
    });
    test('never empty and never collides with a real taxon id', () {
      expect(PlanController.otherBirdId('???'), 'other-bird');
      expect(PlanController.otherBirdId('Northern Cardinal'), isNot('norcar'));
    });
  });

  group('adding for a bird we have no content for', () {
    late InMemoryPlanStore store;
    late PlanController c;
    final repo = realAppContent().repo;
    List<PlanCandidate> two() => [
      PlanCandidate.fromAction(repo.actionById('add-water-source')!),
      PlanCandidate.fromAction(repo.actionById('plant-native-shrub')!),
    ];

    setUp(() async {
      store = InMemoryPlanStore();
      c = PlanController(
        repo: repo,
        openStore: () async => store,
        now: () => DateTime.utc(2026, 11, 17),
      );
      await c.init();
    });

    test(
      'saves the actions under the other-bird id and names the bird',
      () async {
        final r = await c.addForOtherBird(name: 'Mallard', actions: two());
        expect(r.added, hasLength(2));
        expect(
          (await store.load()).every(
            (e) => e.birdIds.contains('other-mallard'),
          ),
          isTrue,
        );
        expect(c.banner, '2 actions added for Mallard');
      },
    );

    test('the plan view counts it as another bird, not a crash', () async {
      await c.addForOtherBird(name: 'Mallard', actions: two());
      expect(c.view!.items.first.unknownBirdCount, 1);
      expect(c.view!.items.first.birds, isEmpty);
    });

    test('adding the same bird again does not duplicate', () async {
      await c.addForOtherBird(name: 'Mallard', actions: two());
      final again = await c.addForOtherBird(name: 'Mallard', actions: two());
      expect(again.added, isEmpty);
      expect(await store.load(), hasLength(2));
      expect(c.banner, contains('already in your plan'));
    });

    test('two different other birds both count', () async {
      await c.addForOtherBird(name: 'Mallard', actions: two());
      await c.addForOtherBird(name: 'Wood Duck', actions: two());
      expect(c.view!.items.first.unknownBirdCount, 2);
    });
  });
}
