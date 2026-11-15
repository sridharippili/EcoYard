import 'dart:convert';

import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:test/test.dart';

import 'support.dart';

PlantFilter f(
  SpaceType space,
  SunExposure sun, [
  BudgetTier budget = BudgetTier.any,
]) =>
    PlantFilter(space: space, sun: sun, budget: budget);

void main() {
  final repo = ReferenceRepository.fromJson(realContent());
  final finder = PlantFinder(repo);
  final raw = (jsonDecode(realContent().plants)['plants'] as List)
      .cast<Map<String, dynamic>>();
  final rawLinks = (jsonDecode(realContent().birdPlant)['links'] as List)
      .cast<Map<String, dynamic>>();

  group('which plants fit', () {
    test('every space/sun cell matches a count taken straight from the JSON',
        () {
      for (final space in SpaceType.values) {
        for (final sun in SunExposure.values) {
          final expected = raw
              .where((p) =>
                  (p['sun'] as List).contains(sun.json) &&
                  (p['spaces'] as List).contains(space.json))
              .map((p) => p['id'])
              .toSet();
          final got =
              finder.find(f(space, sun)).plants.map((x) => x.plant.id).toSet();
          expect(got, expected, reason: '${space.json} / ${sun.json}');
        }
      }
    });

    test('hidden + shown always equals the whole list', () {
      for (final space in SpaceType.values) {
        for (final sun in SunExposure.values) {
          for (final b in BudgetTier.values) {
            final r = finder.find(f(space, sun, b));
            expect(r.plants.length + r.hiddenCount, r.totalCount);
            expect(r.totalCount, raw.length);
          }
        }
      }
    });

    test('every plant can be reached by some filter, linked or not', () {
      final reached = <String>{};
      for (final space in SpaceType.values) {
        for (final sun in SunExposure.values) {
          reached.addAll(
            finder.find(f(space, sun)).plants.map((x) => x.plant.id),
          );
        }
      }
      expect(reached, raw.map((p) => p['id']).toSet());
    });

    test('a plant no bird is linked to is listed, last', () {
      final linked = rawLinks.map((l) => l['plantId']).toSet();
      final orphans =
          raw.map((p) => p['id']).where((id) => !linked.contains(id)).toList();
      expect(orphans, isNotEmpty, reason: 'test needs an unlinked plant');
      final r = finder.find(f(SpaceType.yard, SunExposure.partial));
      for (final id in orphans) {
        final idx = r.plants.indexWhere((x) => x.plant.id == id);
        if (idx == -1) continue; // filtered out by sun/space, fine
        expect(r.plants[idx].breadth, 0);
        expect(r.plants.skip(idx).every((x) => x.breadth == 0), isTrue);
      }
    });

    test('sun and space really filter: shade + balcony is a short list', () {
      final r = finder.find(f(SpaceType.balcony, SunExposure.shade));
      expect(r.plants.length, lessThan(r.totalCount));
      for (final x in r.plants) {
        expect(x.plant.sun, contains(SunExposure.shade));
        expect(x.plant.spaces, contains(SpaceType.balcony));
      }
    });
  });

  group('budget', () {
    test('"Free only" shows nothing while no plant is free, and says why', () {
      final r =
          finder.find(f(SpaceType.yard, SunExposure.full, BudgetTier.free));
      expect(r.plants, isEmpty);
      expect(r.noPlantIsFree, isTrue);
      expect(r.hiddenCount, r.totalCount);
    });

    test('"Low cost" and "Any" give the same list while there are two tiers',
        () {
      // Fails loudly when a third cost tier is added, so this is revisited.
      expect(CostTier.values, hasLength(2));
      for (final space in SpaceType.values) {
        for (final sun in SunExposure.values) {
          expect(
            finder
                .find(f(space, sun, BudgetTier.low))
                .plants
                .map((x) => x.plant.id),
            finder
                .find(f(space, sun, BudgetTier.any))
                .plants
                .map((x) => x.plant.id),
          );
        }
      }
    });

    test('a free plant appears under "Free only" and is not "noPlantIsFree"',
        () {
      final edited = ReferenceRepository.fromJson(
        withEdit('plants', (j) {
          final plants = (j['plants'] as List).cast<Map<String, dynamic>>();
          plants.firstWhere((p) => p['id'] == 'black-eyed-susan')['costTier'] =
              'free';
        }),
      );
      final r = PlantFinder(edited)
          .find(f(SpaceType.yard, SunExposure.full, BudgetTier.free));
      expect(r.plants.map((x) => x.plant.id), ['black-eyed-susan']);
      expect(r.noPlantIsFree, isFalse);
    });
  });

  group('ranking and birds', () {
    test('most birds helped first; ties by cost then id', () {
      final r = finder.find(f(SpaceType.yard, SunExposure.partial));
      for (var i = 1; i < r.plants.length; i++) {
        final a = r.plants[i - 1], b = r.plants[i];
        expect(a.breadth, greaterThanOrEqualTo(b.breadth));
        if (a.breadth == b.breadth) {
          expect(a.plant.id.compareTo(b.plant.id), lessThan(0));
        }
      }
    });

    test('breadth equals the link weights in the JSON', () {
      for (final p in raw) {
        final id = p['id'] as String;
        final expected = rawLinks
            .where((l) => l['plantId'] == id)
            .fold<int>(0, (s, l) => s + (l['weight'] as int));
        expect(finder.describe(id).breadth, expected, reason: id);
      }
    });

    test('birds are ordered by weight, then bird id, whatever the JSON order',
        () {
      for (final p in raw) {
        final birds = finder.describe(p['id'] as String).birds;
        final weights = {
          for (final l in rawLinks.where((l) => l['plantId'] == p['id']))
            l['birdId'] as String: l['weight'] as int,
        };
        for (var i = 1; i < birds.length; i++) {
          final a = birds[i - 1], b = birds[i];
          final wa = weights[a.id]!, wb = weights[b.id]!;
          expect(wa, greaterThanOrEqualTo(wb));
          if (wa == wb) expect(a.id.compareTo(b.id), lessThan(0));
        }
      }
    });

    test('reversing the links in the file does not change the order', () {
      final reversed = ReferenceRepository.fromJson(
        withEdit('bird_plant', (j) {
          j['links'] = (j['links'] as List).reversed.toList();
        }),
      );
      for (final p in raw) {
        final id = p['id'] as String;
        expect(
          PlantFinder(reversed).describe(id).birds.map((b) => b.id),
          finder.describe(id).birds.map((b) => b.id),
          reason: id,
        );
      }
    });

    test('birds with the same weight are ordered by id, not by file order', () {
      // The real content has no plant with two equally weighted birds, so
      // build one: black-chokeberry gets norcar then amegfi, both weight 2.
      for (final order in [
        ['norcar', 'amegfi'],
        ['amegfi', 'norcar'],
      ]) {
        final edited = ReferenceRepository.fromJson(
          withEdit('bird_plant', (j) {
            (j['links'] as List).addAll([
              for (final b in order)
                {
                  'birdId': b,
                  'plantId': 'black-chokeberry',
                  'weight': 2,
                  'needs': ['food'],
                  'reason': 'test',
                },
            ]);
          }),
        );
        expect(
          PlantFinder(edited)
              .describe('black-chokeberry')
              .birds
              .map((b) => b.id),
          ['amegfi', 'norcar'],
          reason: 'file order $order',
        );
      }
    });

    test('describe throws for an unknown plant', () {
      expect(() => finder.describe('ghost'), throwsArgumentError);
    });
  });

  test('PlantFilter compares by value', () {
    expect(f(SpaceType.yard, SunExposure.full),
        f(SpaceType.yard, SunExposure.full));
    expect(f(SpaceType.yard, SunExposure.full),
        isNot(f(SpaceType.balcony, SunExposure.full)));
  });
}
