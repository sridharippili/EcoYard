import 'dart:convert';

import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:test/test.dart';

PlanEntry entry(
  String id, {
  List<String> birds = const ['norcar'],
  String added = '2026-11-14T10:00:00.000Z',
  String? done,
}) =>
    PlanEntry(
      actionId: id,
      birdIds: birds,
      addedOn: added,
      doneOn: done,
      titleSnapshot: 'Title $id',
      bodySnapshot: 'Body $id',
      costSnapshot: 'free',
    );

void main() {
  group('AppSettings', () {
    test('a fresh install is yard / full sun / any budget, not onboarded', () {
      const s = AppSettings.initial;
      expect(s.defaultSpace, SpaceType.yard);
      expect(s.defaultSun, SunExposure.full);
      expect(s.defaultBudget, BudgetTier.any);
      expect(s.onboardingDone, isFalse);
    });

    test('every combination survives a round trip through text', () {
      for (final sp in SpaceType.values) {
        for (final su in SunExposure.values) {
          for (final b in BudgetTier.values) {
            for (final o in [true, false]) {
              final s = AppSettings(
                defaultSpace: sp,
                defaultSun: su,
                defaultBudget: b,
                onboardingDone: o,
              );
              expect(AppSettings.fromMap(s.toMap()), s);
            }
          }
        }
      }
    });

    test('an empty map gives the defaults', () {
      expect(AppSettings.fromMap({}), AppSettings.initial);
    });

    test('garbage, unknown and wrongly cased values fall back, never throw',
        () {
      final s = AppSettings.fromMap({
        AppSettings.keySpace: 'rooftop',
        AppSettings.keySun: '',
        AppSettings.keyBudget: 'PLATINUM',
        AppSettings.keyOnboarded: 'yes',
        'somethingElse': 'x',
      });
      expect(s, AppSettings.initial);
    });

    test('one bad value does not spoil the good ones', () {
      final s = AppSettings.fromMap({
        AppSettings.keySpace: 'balcony',
        AppSettings.keySun: 'nonsense',
        AppSettings.keyBudget: 'free',
        AppSettings.keyOnboarded: 'true',
      });
      expect(s.defaultSpace, SpaceType.balcony);
      expect(s.defaultSun, SunExposure.full);
      expect(s.defaultBudget, BudgetTier.free);
      expect(s.onboardingDone, isTrue);
    });

    test('onboarding is true only for exactly "true"', () {
      for (final v in ['True', '1', 'TRUE', ' true', 'false', '']) {
        expect(
            AppSettings.fromMap({AppSettings.keyOnboarded: v}).onboardingDone,
            isFalse,
            reason: '"$v"');
      }
    });

    test('a place round-trips, and clearing it works', () {
      const p = Place(
        name: 'Basking Ridge',
        admin: 'New Jersey',
        latitude: 40.7,
        longitude: -74.5,
      );
      const s = AppSettings(place: p, useDeviceLocation: true);
      final back = AppSettings.fromMap(s.toMap());
      expect(back.place, p);
      expect(back.useDeviceLocation, isTrue);
      expect(back.copyWith(clearPlace: true).place, isNull);
    });

    test(
        'removing a place really removes it, even in a store that merges '
        'what it is given', () {
      const p = Place(name: 'X', admin: 'Y', latitude: 1.5, longitude: -2.5);
      final stored = <String, String>{...const AppSettings(place: p).toMap()};
      // A store that merges: write the settings again with no place.
      stored.addAll(const AppSettings().toMap());
      expect(AppSettings.fromMap(stored).place, isNull);
    });

    test('no place stored means no place, and location is off by default', () {
      expect(AppSettings.initial.place, isNull);
      expect(AppSettings.initial.useDeviceLocation, isFalse);
      expect(AppSettings.fromMap({}).place, isNull);
    });

    test('a half-written or corrupt place is dropped, not half-used', () {
      for (final m in [
        {AppSettings.keyPlaceName: 'X'},
        {AppSettings.keyPlaceLat: '40.7', AppSettings.keyPlaceLon: '-74.5'},
        {
          AppSettings.keyPlaceName: 'X',
          AppSettings.keyPlaceLat: 'abc',
          AppSettings.keyPlaceLon: '-74.5',
        },
      ]) {
        expect(AppSettings.fromMap(m).place, isNull, reason: '$m');
      }
    });

    test('a stored place keeps the other settings readable', () {
      final s = AppSettings.fromMap({
        AppSettings.keySpace: 'balcony',
        AppSettings.keyPlaceName: 'X',
        AppSettings.keyPlaceLat: 'nonsense',
      });
      expect(s.defaultSpace, SpaceType.balcony);
      expect(s.place, isNull);
    });

    test('copyWith changes only what it is given', () {
      const base = AppSettings(
        defaultSpace: SpaceType.balcony,
        onboardingDone: true,
      );
      final c = base.copyWith(defaultSun: SunExposure.shade);
      expect(c.defaultSpace, SpaceType.balcony);
      expect(c.defaultSun, SunExposure.shade);
      expect(c.onboardingDone, isTrue);
    });
  });

  group('DataSummary', () {
    test('counts the plan, the different birds, and the settings', () {
      final s = DataSummary.of([
        entry('a', birds: ['norcar', 'amegfi']),
        entry('b', birds: ['norcar']),
        entry('c', birds: const []),
      ], {
        'x': '1',
        'y': '2'
      });
      expect(s.planActions, 3);
      expect(s.birdsInPlan, 2);
      expect(s.settingsStored, 2);
      expect(s.isEmpty, isFalse);
    });

    test('nothing stored is empty', () {
      expect(DataSummary.of(const [], const {}).isEmpty, isTrue);
    });
  });

  group('exportMyData', () {
    final when = DateTime.utc(2026, 11, 14, 9);

    Map<String, dynamic> run(List<PlanEntry> plan, AppSettings s) =>
        jsonDecode(exportMyData(plan: plan, settings: s, exportedOn: when))
            as Map<String, dynamic>;

    test('is valid JSON with the plan, the settings and what is not kept', () {
      final j = run([
        entry('a', done: '2026-11-15T00:00:00.000Z'),
      ], AppSettings.initial);
      expect(j['exportedOn'], '2026-11-14T09:00:00.000Z');
      expect((j['plan'] as List).single['actionId'], 'a');
      expect((j['plan'] as List).single['doneOn'], '2026-11-15T00:00:00.000Z');
      expect(j['settings']['defaultSpace'], 'yard');
      expect(j['notKeptOnThisDevice'], ['audio recordings', 'location']);
    });

    test('an empty plan exports an empty list, not null', () {
      expect(run(const [], AppSettings.initial)['plan'], isEmpty);
    });

    test('plan items are in the order they were added', () {
      final j = run([
        entry('late', added: '2026-11-14T12:00:00.000Z'),
        entry('early', added: '2026-11-14T09:00:00.000Z'),
      ], AppSettings.initial);
      expect((j['plan'] as List).map((e) => e['actionId']), ['early', 'late']);
    });

    test('contains no audio or location fields', () {
      final text = exportMyData(
        plan: [entry('a')],
        settings: AppSettings.initial,
        exportedOn: when,
      );
      expect(text.toLowerCase(), isNot(contains('latitude')));
      expect(text.toLowerCase(), isNot(contains('bytes')));
    });

    test('text with quotes and unicode stays valid JSON', () {
      final e = PlanEntry(
        actionId: 'a',
        birdIds: const ['x"y'],
        addedOn: '2026-11-14T09:00:00.000Z',
        titleSnapshot: 'He said "hi" \u{1F426}\nnew line',
        bodySnapshot: 'b',
        costSnapshot: 'free',
      );
      final j = run([e], AppSettings.initial);
      expect((j['plan'] as List).single['title'], contains('\u{1F426}'));
    });
  });
}
