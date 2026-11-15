import 'package:ecoyard/features/plants/plant_finder_controller.dart';
import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  final content = realAppContent();
  DateTime clock = DateTime.utc(2026, 11, 10);

  PlantFinderController make() =>
      PlantFinderController(content: content, now: () => clock);

  setUp(() => clock = DateTime.utc(2026, 11, 10));

  test('starts on yard / full sun / any budget and lists plants', () {
    final c = make();
    expect(c.space, SpaceType.yard);
    expect(c.sun, SunExposure.full);
    expect(c.budget, BudgetTier.any);
    expect(c.result.plants, isNotEmpty);
  });

  test('each setter recomputes the list and tells listeners', () {
    final c = make();
    var calls = 0;
    c.addListener(() => calls++);
    final before = c.result.plants.length;
    c.setSpace(SpaceType.balcony);
    expect(calls, 1);
    expect(c.result.plants.length, lessThan(before));
    c.setSun(SunExposure.shade);
    expect(calls, 2);
    c.setBudget(BudgetTier.free);
    expect(calls, 3);
    expect(c.result.plants, isEmpty);
  });

  test('showDefaults resets everything', () {
    final c = make()
      ..setSpace(SpaceType.containers)
      ..setSun(SunExposure.shade)
      ..setBudget(BudgetTier.free);
    c.showDefaults();
    expect(
      (c.space, c.sun, c.budget),
      (SpaceType.yard, SunExposure.full, BudgetTier.any),
    );
  });

  test('showSmallSpace is balcony and resets sun and budget', () {
    final c = make()
      ..setSun(SunExposure.shade)
      ..setBudget(BudgetTier.free);
    c.showSmallSpace();
    expect(
      (c.space, c.sun, c.budget),
      (SpaceType.balcony, SunExposure.full, BudgetTier.any),
    );
  });

  test('a preset does not stick: defaults after Small Space is yard again', () {
    final c = make()..showSmallSpace();
    c.showDefaults();
    expect(c.space, SpaceType.yard);
  });

  group('the free first step', () {
    HabitatAction? expected(
      int month,
      SpaceType s,
      SunExposure u,
      BudgetTier b,
    ) => content.engine
        .recommend(
          HabitatQuery(
            birdId: null,
            space: s,
            sun: u,
            budget: b,
            month: month,
            regionCode: content.repo.region,
          ),
        )
        .freeFirstStep;

    test('matches the engine for every month and space', () {
      for (var m = 1; m <= 12; m++) {
        for (final s in SpaceType.values) {
          clock = DateTime.utc(2026, m, 15);
          final c = make()..setSpace(s);
          expect(
            c.freeFirstStep?.id,
            expected(m, s, c.sun, c.budget)?.id,
            reason: 'month $m ${s.json}',
          );
        }
      }
    });

    test('is a free action, and exists in every month for a yard', () {
      for (var m = 1; m <= 12; m++) {
        clock = DateTime.utc(2026, m, 15);
        final step = make().freeFirstStep;
        expect(step, isNotNull, reason: 'month $m has no free first step');
        expect(step!.costTier, CostTier.free);
        expect(step.months, contains(m));
      }
    });

    test('is still shown on "Free only", where there are no plants', () {
      final c = make()..setBudget(BudgetTier.free);
      expect(c.result.plants, isEmpty);
      expect(c.freeFirstStep, isNotNull);
    });

    test('follows the clock: a new month gives that month\'s answer', () {
      clock = DateTime.utc(2026, 1, 5);
      final jan = make().freeFirstStep!.id;
      clock = DateTime.utc(2026, 7, 5);
      final jul = make().freeFirstStep!.id;
      expect(
        jan,
        expected(1, SpaceType.yard, SunExposure.full, BudgetTier.any)!.id,
      );
      expect(
        jul,
        expected(7, SpaceType.yard, SunExposure.full, BudgetTier.any)!.id,
      );
    });
  });

  test('describe gives a plant with its birds', () {
    final c = make();
    expect(c.describe('black-eyed-susan').birds, isNotEmpty);
    expect(() => c.describe('ghost'), throwsArgumentError);
  });
}
