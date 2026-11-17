import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bird_audio/bird_audio.dart';
import 'package:ecoyard/features/settings/settings_controller.dart';
import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

PlanCandidate cand(String id) => PlanCandidate(
  actionId: id,
  title: 'Title $id',
  body: 'Body $id',
  costTier: CostTier.free,
);

void main() {
  late Directory tmp;
  late InMemoryAppStorage storage;
  late SettingsController c;
  late FakeExporter exporter;
  late FakeReminders reminders;
  final clock = DateTime.utc(2026, 11, 14, 9);

  SettingsController make([Future<AppStorage> Function()? open]) =>
      SettingsController(
        storage: open ?? () async => storage,
        audio: AudioCache(tempDir: () async => tmp),
        now: () => clock,
        exporter: exporter,
        reminders: reminders,
      );

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ecoyard_sc_');
    storage = InMemoryAppStorage();
    exporter = FakeExporter();
    reminders = FakeReminders();
    c = make();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  group('loading', () {
    test('empty storage gives the defaults, ready', () async {
      await c.init();
      expect(c.state, SettingsLoadState.ready);
      expect(c.settings, AppSettings.initial);
    });

    test('saved values are read back', () async {
      await storage.settings.setAll(
        const AppSettings(
          defaultSpace: SpaceType.balcony,
          defaultBudget: BudgetTier.free,
          onboardingDone: true,
        ).toMap(),
      );
      await c.init();
      expect(c.settings.defaultSpace, SpaceType.balcony);
      expect(c.settings.defaultBudget, BudgetTier.free);
      expect(c.settings.onboardingDone, isTrue);
    });

    test('corrupted stored values give defaults, not a crash', () async {
      await storage.settings.setAll({
        AppSettings.keySpace: '\u0000',
        AppSettings.keyBudget: '???',
      });
      await c.init();
      expect(c.state, SettingsLoadState.ready);
      expect(c.settings, AppSettings.initial);
    });

    test(
      'a storage that cannot open is "failed" with defaults; retry works',
      () async {
        var n = 0;
        c = make(() async {
          if (++n == 1) throw StateError('locked');
          return storage;
        });
        await c.init();
        expect(c.state, SettingsLoadState.failed);
        expect(c.settings, AppSettings.initial);
        await c.init();
        expect(c.state, SettingsLoadState.ready);
      },
    );

    test(
      'a storage that never answers fails after 5 seconds, not never',
      () async {
        final never = Completer<AppStorage>();
        c = make(() => never.future);
        await c.init(); // returns once the timeout fires
        expect(c.state, SettingsLoadState.failed);
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );

    test('two init calls at once open the storage once', () async {
      var opens = 0;
      final gate = Completer<AppStorage>();
      c = make(() {
        opens++;
        return gate.future;
      });
      final a = c.init(), b = c.init();
      gate.complete(storage);
      await Future.wait([a, b]);
      expect(opens, 1);
    });
  });

  group('saving defaults', () {
    test('persists and updates the value', () async {
      await c.init();
      expect(await c.saveDefaults(space: SpaceType.containers), isTrue);
      expect(c.settings.defaultSpace, SpaceType.containers);
      expect(
        AppSettings.fromMap(await storage.settings.loadAll()).defaultSpace,
        SpaceType.containers,
      );
    });

    test('changing one value keeps the others', () async {
      await c.init();
      await c.saveDefaults(space: SpaceType.balcony);
      await c.saveDefaults(sun: SunExposure.shade);
      expect(c.settings.defaultSpace, SpaceType.balcony);
      expect(c.settings.defaultSun, SunExposure.shade);
    });

    test('a failed write keeps the old value and says so; the next success '
        'clears the message', () async {
      final mem = InMemorySettingsStore();
      storage = InMemoryAppStorage(settings: mem);
      c = make();
      await c.init();
      mem.failNext = StateError('disk full');
      expect(await c.saveDefaults(space: SpaceType.balcony), isFalse);
      expect(c.settings.defaultSpace, SpaceType.yard);
      expect(c.saveError, isNotNull);
      expect(await c.saveDefaults(space: SpaceType.balcony), isTrue);
      expect(c.saveError, isNull);
    });

    test('a save after a failed load recovers the state', () async {
      var n = 0;
      c = make(() async {
        if (++n == 1) throw StateError('x');
        return storage;
      });
      await c.init();
      expect(c.state, SettingsLoadState.failed);
      expect(await c.saveDefaults(sun: SunExposure.partial), isTrue);
      expect(c.state, SettingsLoadState.ready);
    });

    test(
      'two quick saves both land: the second does not overwrite the first',
      () async {
        await c.init();
        final a = c.saveDefaults(space: SpaceType.balcony);
        final b = c.saveDefaults(sun: SunExposure.shade);
        expect(await a, isTrue);
        expect(await b, isTrue);
        expect(c.settings.defaultSpace, SpaceType.balcony);
        expect(c.settings.defaultSun, SunExposure.shade);
        final stored = AppSettings.fromMap(await storage.settings.loadAll());
        expect(stored.defaultSpace, SpaceType.balcony);
        expect(stored.defaultSun, SunExposure.shade);
      },
    );

    test(
      'many saves started together end in the last value, in order',
      () async {
        await c.init();
        final all = [
          for (final s in SpaceType.values) c.saveDefaults(space: s),
          c.saveDefaults(space: SpaceType.balcony),
        ];
        await Future.wait(all);
        expect(c.settings.defaultSpace, SpaceType.balcony);
        expect(
          AppSettings.fromMap(await storage.settings.loadAll()).defaultSpace,
          SpaceType.balcony,
        );
      },
    );

    test('a failed save does not stop the next one in the queue', () async {
      final mem = InMemorySettingsStore();
      storage = InMemoryAppStorage(settings: mem);
      c = make();
      await c.init();
      mem.failNext = StateError('x');
      final a = c.saveDefaults(space: SpaceType.balcony);
      final b = c.saveDefaults(sun: SunExposure.shade);
      expect(await a, isFalse);
      expect(await b, isTrue);
      expect(c.settings.defaultSun, SunExposure.shade);
      expect(c.settings.defaultSpace, SpaceType.yard);
    });

    test('after a failed load, a save reads the stored settings first and '
        'never writes defaults over them', () async {
      final mem = InMemorySettingsStore({
        AppSettings.keySpace: 'balcony',
        'from-a-newer-version': 'keep me',
      });
      storage = InMemoryAppStorage(settings: mem);
      c = make();
      mem.failNext = StateError('unreadable');
      await c.init();
      expect(c.state, SettingsLoadState.failed);

      expect(await c.saveDefaults(sun: SunExposure.shade), isTrue);
      expect(
        c.settings.defaultSpace,
        SpaceType.balcony,
        reason: 'the stored value must survive',
      );
      final stored = await mem.loadAll();
      expect(stored['from-a-newer-version'], 'keep me');
      expect(stored[AppSettings.keySpace], 'balcony');
    });

    test('if the stored settings still cannot be read, the save is refused '
        'and nothing is written', () async {
      final mem = InMemorySettingsStore({AppSettings.keySpace: 'balcony'});
      var reads = 0;
      c = make(() async {
        reads++;
        throw StateError('storage down');
      });
      await c.init();
      expect(await c.saveDefaults(sun: SunExposure.shade), isFalse);
      expect(c.saveError, isNotNull);
      expect(await mem.loadAll(), {AppSettings.keySpace: 'balcony'});
      expect(reads, 2, reason: 'one load, one retry before the save');
    });

    test('markOnboarded persists', () async {
      await c.init();
      await c.markOnboarded();
      expect(c.settings.onboardingDone, isTrue);
      expect(
        AppSettings.fromMap(await storage.settings.loadAll()).onboardingDone,
        isTrue,
      );
    });

    test('listeners are told', () async {
      await c.init();
      var n = 0;
      c.addListener(() => n++);
      await c.saveDefaults(space: SpaceType.balcony);
      expect(n, 1);
    });
  });

  group('my data', () {
    Future<void> seed() async {
      await storage.plans.add(
        birdId: 'norcar',
        actions: [cand('a1'), cand('a2')],
        now: clock,
      );
      await storage.plans.add(
        birdId: 'amegfi',
        actions: [cand('a1')],
        now: clock,
      );
      await storage.settings.setAll(AppSettings.initial.toMap());
    }

    test('the summary counts what is really stored', () async {
      await seed();
      final s = await c.summary();
      expect(s.planActions, 2);
      expect(s.birdsInPlan, 2);
      expect(s.settingsStored, AppSettings.initial.toMap().length);
    });

    test('an empty store has an empty summary', () async {
      expect((await c.summary()).isEmpty, isTrue);
    });

    test('the export is JSON with the plan, settings and the clock', () async {
      await seed();
      final j = jsonDecode(await c.exportText()) as Map<String, dynamic>;
      expect(j['exportedOn'], '2026-11-14T09:00:00.000Z');
      expect((j['plan'] as List).map((e) => e['actionId']).toSet(), {
        'a1',
        'a2',
      });
      expect(j['settings']['defaultSpace'], 'yard');
    });

    test(
      'summary and export throw when storage cannot be read, never lie',
      () async {
        c = make(() async => throw StateError('gone'));
        await expectLater(c.summary(), throwsA(anything));
        await expectLater(c.exportText(), throwsA(anything));
      },
    );
  });

  group('exporting as a file', () {
    test('hands the share sheet exactly the export text', () async {
      await storage.plans.add(
        birdId: 'norcar',
        actions: [cand('a1')],
        now: clock,
      );
      await storage.settings.setAll(AppSettings.initial.toMap());
      final outcome = await c.exportFile();
      expect(outcome, ExportOutcome.shared);
      final sent = jsonDecode(exporter.shared.single) as Map<String, dynamic>;
      expect(sent['exportedOn'], '2026-11-14T09:00:00.000Z');
      expect((sent['plan'] as List).single['actionId'], 'a1');
      expect(exporter.shared.single, await c.exportText());
    });

    test('a dismissed sheet is reported as dismissed', () async {
      exporter.outcome = ExportOutcome.dismissed;
      expect(await c.exportFile(), ExportOutcome.dismissed);
    });

    test(
      'if the data cannot be read, nothing is shared and it throws',
      () async {
        c = make(() async => throw StateError('gone'));
        await expectLater(c.exportFile(), throwsA(anything));
        expect(exporter.shared, isEmpty);
      },
    );

    test('an empty app still exports a valid, empty plan', () async {
      await c.exportFile();
      final sent = jsonDecode(exporter.shared.single) as Map<String, dynamic>;
      expect(sent['plan'], isEmpty);
    });
  });

  group('delete everything', () {
    File leftover() =>
        File('${tmp.path}/ecoyard_123.m4a')..writeAsBytesSync([1]);

    test(
      'erases plan and settings, resets to a first launch, sweeps audio',
      () async {
        await storage.plans.add(
          birdId: 'norcar',
          actions: [cand('a1')],
          now: clock,
        );
        await c.init();
        await c.saveDefaults(space: SpaceType.balcony);
        await c.markOnboarded();
        final f = leftover();

        await c.deleteEverything();

        expect(await storage.plans.load(), isEmpty);
        expect(await storage.settings.loadAll(), isEmpty);
        expect(c.settings, AppSettings.initial);
        expect(c.settings.onboardingDone, isFalse);
        expect(c.state, SettingsLoadState.ready);
        expect(f.existsSync(), isFalse);
      },
    );

    test('a failed erase throws and changes nothing, audio included', () async {
      await storage.plans.add(
        birdId: 'norcar',
        actions: [cand('a1')],
        now: clock,
      );
      await c.init();
      await c.saveDefaults(space: SpaceType.balcony);
      final f = leftover();
      storage.failWipe = StateError('trap');

      await expectLater(c.deleteEverything(), throwsA(anything));
      expect(exporter.sweeps, 0, reason: 'a failed erase sweeps nothing');

      expect(await storage.plans.load(), hasLength(1));
      expect(
        c.settings.defaultSpace,
        SpaceType.balcony,
        reason: 'screen must not claim an erase that did not happen',
      );
      expect(f.existsSync(), isTrue);
    });

    test('works on an already empty app', () async {
      await c.deleteEverything();
      expect(c.settings, AppSettings.initial);
    });

    test('works when settings never loaded (storage failed once)', () async {
      var n = 0;
      c = make(() async {
        if (++n == 1) throw StateError('x');
        return storage;
      });
      await c.init();
      await c.deleteEverything();
      expect(c.state, SettingsLoadState.ready);
    });

    test('a leftover recording that is not ours is kept', () async {
      final other = File('${tmp.path}/someone_else.m4a')..writeAsBytesSync([1]);
      await c.deleteEverything();
      expect(other.existsSync(), isTrue);
    });
  });
}
