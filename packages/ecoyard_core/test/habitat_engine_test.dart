import 'dart:convert';
import 'dart:io';

import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Loads fixtures/engine_cases.json when the user has promoted it; until then
/// the draft next to the tests. Agents cannot edit fixtures/, so a promoted
/// file is the locked source of truth.
({List<Map<String, dynamic>> cases, String source}) loadCases() {
  final root = repoRoot().path;
  final promoted = File('$root/fixtures/engine_cases.json');
  final draft =
      File('$root/packages/ecoyard_core/test/engine_cases.draft.json');
  final file = promoted.existsSync() ? promoted : draft;
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  if (json['schemaVersion'] != 1) {
    throw StateError('engine cases: unsupported schemaVersion');
  }
  return (
    cases: (json['cases'] as List).cast<Map<String, dynamic>>(),
    source: promoted.existsSync()
        ? 'fixtures/engine_cases.json (locked)'
        : 'engine_cases.draft.json (NOT YET PROMOTED)',
  );
}

HabitatQuery queryOf(Map<String, dynamic> i) => HabitatQuery(
      birdId: i['birdId'] as String?,
      space: SpaceType.values.firstWhere((e) => e.json == i['space']),
      sun: SunExposure.values.firstWhere((e) => e.json == i['sun']),
      budget: BudgetTier.values.firstWhere((e) => e.json == i['budget']),
      month: i['month'] as int,
      regionCode: i['regionCode'] as String,
      journalBirdIds: {...(i['journal'] as List).cast<String>()},
    );

void main() {
  late ReferenceRepository repo;
  late HabitatEngine engine;

  setUpAll(() {
    repo = ReferenceRepository.fromJson(realContent());
    engine = HabitatEngine(repo);
  });

  group('the case table', () {
    final loaded = loadCases();
    // ignore: avoid_print
    print('engine cases loaded from: ${loaded.source}');

    test('has at least 20 cases', () {
      expect(loaded.cases.length, greaterThanOrEqualTo(20));
    });

    for (final c in loaded.cases) {
      test('${c['id']}', () {
        final query = queryOf(c['input'] as Map<String, dynamic>);
        final expect_ = c['expect'] as Map<String, dynamic>;

        if (expect_.containsKey('error')) {
          final matcher = switch (expect_['error']) {
            'ArgumentError' => throwsA(isA<ArgumentError>()),
            'UnsupportedRegionException' =>
              throwsA(isA<UnsupportedRegionException>()),
            final other => throw StateError('unknown error kind $other'),
          };
          expect(() => engine.recommend(query), matcher,
              reason: c['why'] as String);
          return;
        }

        final r = engine.recommend(query);
        final why = c['why'] as String;
        expect(r.actions.map((a) => a.id).toList(), expect_['actionIds'],
            reason: 'actions. $why');
        expect(r.freeFirstStep?.id, expect_['freeFirstStepId'],
            reason: 'free first step. $why');
        expect(r.plants.map((p) => p.plant.id).toList(), expect_['plantIds'],
            reason: 'plants. $why');
        expect(r.plantsHiddenByFilters, expect_['plantsHidden'],
            reason: 'hidden plants. $why');
        expect(r.isGeneric, expect_['isGeneric'], reason: 'isGeneric. $why');
        expect(r.unmetNeeds.map((n) => n.json).toList(), expect_['unmetNeeds'],
            reason: 'unmet needs. $why');

        final moreBudget = expect_['moreBudget'] as Map<String, dynamic>?;
        if (moreBudget != null) {
          for (final e in moreBudget.entries) {
            final n = r.supportNeeds.firstWhere((n) => n.need.json == e.key);
            expect(n.moreBudgetActionIds, (e.value as List).cast<String>(),
                reason: 'moreBudget for ${e.key}. $why');
          }
        }

        final also = expect_['alsoHelps'] as Map<String, dynamic>?;
        if (also != null) {
          for (final e in also.entries) {
            final p = r.plants.firstWhere((p) => p.plant.id == e.key);
            expect(p.alsoHelps, (e.value as List).cast<String>(),
                reason: 'alsoHelps for ${e.key}. $why');
          }
        }
      });
    }
  });

  group('rules that must hold for every input', () {
    final spaces = SpaceType.values;
    final suns = SunExposure.values;
    final budgets = BudgetTier.values;

    test('every bird x month x space x sun x budget (and unknown bird)', () {
      final birdIds = <String?>[null, ...repo.birds.map((b) => b.id)];
      var runs = 0;

      for (final bird in birdIds) {
        for (var month = 1; month <= 12; month++) {
          for (final space in spaces) {
            for (final sun in suns) {
              for (final budget in budgets) {
                final q = HabitatQuery(
                  birdId: bird,
                  space: space,
                  sun: sun,
                  budget: budget,
                  month: month,
                  regionCode: repo.region,
                  journalBirdIds: {'norcar', 'ghost'},
                );
                final r = engine.recommend(q);
                runs++;
                final where =
                    '$bird m$month ${space.json} ${sun.json} ${budget.json}';

                // Never more than three, and no repeats.
                expect(r.actions.length, lessThanOrEqualTo(3), reason: where);
                final ids = r.actions.map((a) => a.id).toList();
                expect(ids.toSet().length, ids.length, reason: where);

                // Slot 1 is free whenever any free action is possible.
                final anyFree = repo.actions.any((a) =>
                    a.costTier == CostTier.free &&
                    a.months.contains(month) &&
                    a.spaces.contains(space) &&
                    (a.forBirdIds.isEmpty ||
                        (bird != null && a.forBirdIds.contains(bird))));
                if (anyFree) {
                  expect(r.actions.first.costTier, CostTier.free,
                      reason: where);
                  expect(r.freeFirstStep, isNotNull, reason: where);
                }

                for (final a in r.actions) {
                  // In season, fits the space and budget, right bird.
                  expect(a.months, contains(month), reason: '$where ${a.id}');
                  expect(a.spaces, contains(space), reason: '$where ${a.id}');
                  expect(budget.allows(a.costTier), isTrue,
                      reason: '$where ${a.id}');
                  if (a.forBirdIds.isNotEmpty) {
                    expect(a.forBirdIds, contains(bird),
                        reason: '$where ${a.id}');
                  }
                }

                // Plants fit the sun, space and budget; ids are real.
                if (budget == BudgetTier.free) {
                  expect(r.plants, isEmpty, reason: where);
                }
                for (final p in r.plants) {
                  expect(repo.plantById(p.plant.id), isNotNull, reason: where);
                  expect(p.plant.sun, contains(sun),
                      reason: '$where ${p.plant.id}');
                  expect(p.plant.spaces, contains(space),
                      reason: '$where ${p.plant.id}');
                }
                final plantIds = r.plants.map((p) => p.plant.id).toList();
                expect(plantIds.toSet().length, plantIds.length, reason: where);

                // Plants come best first.
                for (var i = 1; i < r.plants.length; i++) {
                  expect(r.plants[i - 1].score,
                      greaterThanOrEqualTo(r.plants[i].score),
                      reason: where);
                }

                // No padding: after the first slot, each action covers a need
                // that the earlier ones did not.
                final target = bird == null
                    ? Need.values.toSet()
                    : {
                        for (final n in repo.birdById(bird)!.supportNeeds)
                          n.need
                      };
                final covered = <Need>{};
                for (var k = 0; k < r.actions.length; k++) {
                  final fresh = r.actions[k].needs
                      .where((n) => target.contains(n) && !covered.contains(n));
                  if (k > 0) {
                    expect(fresh, isNotEmpty,
                        reason:
                            '$where: ${r.actions[k].id} repeats covered needs');
                  }
                  covered.addAll(r.actions[k].needs.where(target.contains));
                }

                // Budget-blocked remedies really cost more than the budget
                // allows and are in season and fit the space.
                for (final n in r.supportNeeds) {
                  for (final id in n.moreBudgetActionIds) {
                    final act = repo.actionById(id)!;
                    expect(budget.allows(act.costTier), isFalse, reason: where);
                    expect(act.months, contains(month), reason: where);
                    expect(act.spaces, contains(space), reason: where);
                  }
                }

                // Need coverage is consistent with what is shown.
                for (final n in r.supportNeeds) {
                  expect(n.remedyActionIds, containsAll(n.shownActionIds),
                      reason: where);
                  for (final id in n.shownActionIds) {
                    expect(ids, contains(id), reason: where);
                  }
                  expect(
                      n.laterActionIds
                          .toSet()
                          .intersection(n.remedyActionIds.toSet()),
                      isEmpty,
                      reason:
                          '$where: an action is either available now or later');
                }

                // Deterministic.
                final again = engine.recommend(q);
                expect(again.actions.map((a) => a.id).toList(), ids,
                    reason: where);
                expect(again.plants.map((p) => p.plant.id).toList(), plantIds,
                    reason: where);
              }
            }
          }
        }
      }
      expect(runs, 11 * 12 * 3 * 3 * 3);
    });
  });

  group('behaviour the UI will rely on', () {
    HabitatQuery q(String? bird,
            {int month = 1,
            SpaceType space = SpaceType.yard,
            SunExposure sun = SunExposure.full,
            BudgetTier budget = BudgetTier.low}) =>
        HabitatQuery(
          birdId: bird,
          space: space,
          sun: sun,
          budget: budget,
          month: month,
          regionCode: repo.region,
        );

    test('an off-season remedy is reported as "later", not as a remedy', () {
      final r = engine.recommend(q('bkcchi', month: 1));
      final safety = r.supportNeeds.firstWhere((n) => n.need == Need.safety);
      expect(safety.hasRemedy, isFalse);
      expect(safety.laterActionIds, ['mark-windows']);
    });

    test('a remedy that exists but is not shown is "also possible"', () {
      // October, cardinal: mark-windows is available for safety but the three
      // slots go to leaf cover, water and a native shrub.
      final r = engine.recommend(q('norcar', month: 10));
      final safety = r.supportNeeds.firstWhere((n) => n.need == Need.safety);
      expect(safety.remedyActionIds, ['mark-windows']);
      expect(safety.hasRemedy, isTrue);
      expect(safety.coveredByShownActions, isFalse);
      expect(r.actions.map((a) => a.id), isNot(contains('mark-windows')));
      expect(r.unmetNeeds, isNot(contains(Need.safety)));
    });

    test('a signature action beats a generic one for its bird', () {
      final gold = engine.recommend(q('amegfi', month: 10));
      expect(gold.actions.first.id, 'leave-seed-heads');
      // The same action is NOT preferred for a bird it is not featured for.
      final cardinal = engine.recommend(q('norcar', month: 10));
      expect(cardinal.actions.first.id, 'keep-leaf-cover');
    });

    test('the nest box is shown to nest-box birds, never to others', () {
      for (final bird in ['bkcchi', 'tuftit', 'carwre']) {
        final ids =
            engine.recommend(q(bird, month: 2)).actions.map((a) => a.id);
        expect(ids, contains('add-nest-box'), reason: bird);
      }
      for (final bird in ['norcar', 'amegfi', 'rthhum', 'dowwoo']) {
        for (var m = 1; m <= 12; m++) {
          final ids =
              engine.recommend(q(bird, month: m)).actions.map((a) => a.id);
          expect(ids, isNot(contains('add-nest-box')), reason: '$bird m$m');
        }
      }
    });

    test('no padding: an action that repeats a covered need is not shown', () {
      // Hummingbird in July on a balcony: water is not its need, and food is
      // covered by the first action, so only ONE action is shown.
      final r = engine.recommend(q('rthhum',
          month: 7, space: SpaceType.balcony, sun: SunExposure.full));
      expect(r.actions.map((a) => a.id), ['skip-pesticides']);
      // Cardinal in January: water and leaf cover, not a second water action.
      final c = engine.recommend(q('norcar', month: 1));
      expect(
          c.actions.map((a) => a.id), ['keep-leaf-cover', 'add-water-source']);
    });

    test('a need blocked only by budget is not reported as hopeless', () {
      final r =
          engine.recommend(q('norcar', month: 10, budget: BudgetTier.free));
      final nesting = r.supportNeeds.firstWhere((n) => n.need == Need.nesting);
      expect(nesting.hasRemedy, isFalse);
      expect(nesting.moreBudgetActionIds, ['plant-native-shrub']);
      final safety = r.supportNeeds.firstWhere((n) => n.need == Need.safety);
      expect(safety.moreBudgetActionIds, ['mark-windows']);
      // With enough budget they are plain remedies and not budget-blocked.
      final rich = engine.recommend(q('norcar', month: 10));
      for (final n in rich.supportNeeds) {
        expect(n.moreBudgetActionIds, isEmpty, reason: n.need.json);
      }
    });

    test('the hummingbird has no water need, so water is not a need to cover',
        () {
      final r = engine.recommend(q('rthhum', month: 7));
      expect(r.supportNeeds.map((n) => n.need), isNot(contains(Need.water)));
    });

    test('plant remedies come from the bird\'s own links', () {
      final r = engine.recommend(q('norcar', month: 1));
      final nesting = r.supportNeeds.firstWhere((n) => n.need == Need.nesting);
      expect(nesting.remedyPlantIds, ['arrowwood-viburnum']);
    });

    test('a generic answer never includes a bird-specific action', () {
      for (var m = 1; m <= 12; m++) {
        final ids =
            engine.recommend(q(null, month: m)).actions.map((a) => a.id);
        expect(ids, isNot(contains('add-nest-box')));
        expect(ids, isNot(contains('leave-dead-wood')));
      }
    });

    test('an unknown journal id is ignored', () {
      final plain = engine.recommend(q('amegfi', month: 10));
      final withGhost = engine.recommend(HabitatQuery(
        birdId: 'amegfi',
        space: SpaceType.yard,
        sun: SunExposure.full,
        budget: BudgetTier.low,
        month: 10,
        regionCode: repo.region,
        journalBirdIds: {'ghost-bird'},
      ));
      expect(withGhost.plants.map((p) => p.plant.id),
          plain.plants.map((p) => p.plant.id));
    });

    test('the bird being asked about does not count as its own journal entry',
        () {
      final r = engine.recommend(HabitatQuery(
        birdId: 'norcar',
        space: SpaceType.yard,
        sun: SunExposure.full,
        budget: BudgetTier.low,
        month: 5,
        regionCode: repo.region,
        journalBirdIds: {'norcar'},
      ));
      for (final p in r.plants) {
        expect(p.alsoHelps, isEmpty);
      }
    });

    test('the engine reads the region from the content', () {
      expect(repo.region, 'us-ne');
    });
  });
}
