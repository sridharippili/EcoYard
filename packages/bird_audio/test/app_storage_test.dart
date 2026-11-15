import 'dart:io';

import 'package:bird_audio/bird_audio.dart';
import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

PlanCandidate cand(String id) => PlanCandidate(
      actionId: id,
      title: 'Title $id',
      body: 'Body $id',
      costTier: CostTier.free,
    );

final t0 = DateTime.utc(2026, 11, 14, 10);

void settingsContract(Future<SettingsStore> Function() create) {
  late SettingsStore s;
  setUp(() async => s = await create());

  test('starts empty', () async {
    expect(await s.loadAll(), isEmpty);
  });

  test('stores and reads values, and a later write replaces an earlier one',
      () async {
    await s.setAll({'a': '1', 'b': '2'});
    await s.setAll({'b': '3'});
    expect(await s.loadAll(), {'a': '1', 'b': '3'});
  });

  test('clear removes everything, and the store still works afterwards',
      () async {
    await s.setAll({'a': '1'});
    await s.clear();
    expect(await s.loadAll(), isEmpty);
    await s.setAll({'a': '2'});
    expect(await s.loadAll(), {'a': '2'});
  });

  test('clearing an empty store is fine', () async {
    await s.clear();
    expect(await s.loadAll(), isEmpty);
  });

  test('empty maps, quotes, unicode and long values round-trip', () async {
    await s.setAll({});
    final long = 'x' * 50000;
    await s.setAll({
      "k'; DROP TABLE settings; --": 'v"\n\u{1F426}',
      'long': long,
      'empty': '',
    });
    final all = await s.loadAll();
    expect(all["k'; DROP TABLE settings; --"], 'v"\n\u{1F426}');
    expect(all['long'], long);
    expect(all['empty'], '');
  });

  test('typed settings survive a save and a load', () async {
    const wanted = AppSettings(
      defaultSpace: SpaceType.containers,
      defaultSun: SunExposure.shade,
      defaultBudget: BudgetTier.free,
      onboardingDone: true,
    );
    await s.setAll(wanted.toMap());
    expect(AppSettings.fromMap(await s.loadAll()), wanted);
  });

  test('corrupted stored values fall back to defaults instead of crashing',
      () async {
    await s.setAll({
      AppSettings.keySpace: '\u0000garbage',
      AppSettings.keyBudget: 'PLATINUM',
      AppSettings.keyOnboarded: 'maybe',
      'unknown-key': 'whatever',
    });
    expect(AppSettings.fromMap(await s.loadAll()), AppSettings.initial);
  });
}

void main() {
  sqfliteFfiInit();
  late Directory tmp;
  var n = 0;
  setUpAll(() => tmp = Directory.systemTemp.createTempSync('ecoyard_storage_'));
  tearDownAll(() => tmp.deleteSync(recursive: true));
  String dbPath() => '${tmp.path}/db_${n++}.db';

  Future<SqliteAppStorage> open([String? path]) => SqliteAppStorage.open(
        path: path ?? dbPath(),
        factory: databaseFactoryFfi,
      );

  group('InMemorySettingsStore', () {
    settingsContract(() async => InMemorySettingsStore());
  });

  group('SqfliteSettingsStore', () {
    settingsContract(() async => (await open()).settings);

    test('a failure part-way through setAll writes nothing', () async {
      final path = dbPath();
      final st = await open(path);
      final raw = await databaseFactoryFfi.openDatabase(path); // same handle
      await raw.execute('''
CREATE TRIGGER trap BEFORE INSERT ON settings
WHEN NEW.key = 'boom'
BEGIN SELECT RAISE(ABORT, 'trap'); END''');
      await expectLater(
        st.settings.setAll({'first': '1', 'boom': '2'}),
        throwsA(anything),
      );
      expect(await st.settings.loadAll(), isEmpty);
      await st.close();
    });

    test('settings survive closing and reopening the file', () async {
      final path = dbPath();
      var st = await open(path);
      await st.settings.setAll({'a': '1'});
      await st.close();
      st = await open(path);
      expect(await st.settings.loadAll(), {'a': '1'});
      await st.close();
    });
  });

  group('SqliteAppStorage', () {
    test('plan and settings share one open database', () async {
      final st = await open();
      await st.plans.add(birdId: 'norcar', actions: [cand('a1')], now: t0);
      await st.settings.setAll({'a': '1'});
      // Closing the plan store must not close the shared database.
      await st.plans.close();
      expect(await st.settings.loadAll(), {'a': '1'});
      expect(await st.plans.load(), hasLength(1));
      await st.close();
    });

    test('wipeAll erases the plan (and its birds) and the settings', () async {
      final path = dbPath();
      final st = await open(path);
      await st.plans.add(
        birdId: 'norcar',
        actions: [cand('a1'), cand('a2')],
        now: t0,
      );
      await st.plans.add(birdId: 'amegfi', actions: [cand('a1')], now: t0);
      await st.settings.setAll(AppSettings.initial.toMap());

      await st.wipeAll();

      expect(await st.plans.load(), isEmpty);
      expect(await st.settings.loadAll(), isEmpty);
      final raw = await databaseFactoryFfi.openDatabase(path);
      expect(await raw.query('plan_actions'), isEmpty);
      expect(await raw.query('plan_action_birds'), isEmpty);
      expect(await raw.query('settings'), isEmpty);
      await st.close();
    });

    test('after a wipe the storage is still usable', () async {
      final st = await open();
      await st.plans.add(birdId: 'norcar', actions: [cand('a1')], now: t0);
      await st.wipeAll();
      await st.plans.add(birdId: 'amegfi', actions: [cand('b1')], now: t0);
      await st.settings.setAll({'x': 'y'});
      expect((await st.plans.load()).single.actionId, 'b1');
      expect(await st.settings.loadAll(), {'x': 'y'});
      await st.close();
    });

    test(
        'wipeAll is all-or-nothing: if the settings cannot be erased the '
        'plan is kept and the error is thrown', () async {
      final path = dbPath();
      final st = await open(path);
      await st.plans.add(birdId: 'norcar', actions: [cand('a1')], now: t0);
      await st.settings.setAll({'a': '1'});
      final raw = await databaseFactoryFfi.openDatabase(path);
      await raw.execute('''
CREATE TRIGGER trap BEFORE DELETE ON settings
BEGIN SELECT RAISE(ABORT, 'trap'); END''');

      await expectLater(st.wipeAll(), throwsA(anything));
      expect(await st.plans.load(), hasLength(1), reason: 'plan must survive');
      expect(await st.settings.loadAll(), {'a': '1'});
      await st.close();
    });

    test('wiping an empty database is fine', () async {
      final st = await open();
      await st.wipeAll();
      expect(await st.plans.load(), isEmpty);
      await st.close();
    });

    test('the file does not keep the erased text', () async {
      final path = dbPath();
      final st = await open(path);
      const marker = 'ZZ-UNIQUE-MARKER-ZZ';
      await st.plans.add(
        birdId: 'norcar',
        actions: [
          PlanCandidate(
            actionId: 'a1',
            title: marker,
            body: marker * 200,
            costTier: CostTier.free,
          ),
        ],
        now: t0,
      );
      await st.close();
      expect(File(path).readAsBytesSync().length, greaterThan(0));

      final st2 = await open(path);
      await st2.wipeAll();
      await st2.close();
      final bytes = String.fromCharCodes(File(path).readAsBytesSync());
      expect(bytes.contains(marker), isFalse,
          reason: 'VACUUM should drop the erased text from the file');
    });
  });

  group('InMemoryAppStorage', () {
    test('wipeAll clears both, and a failed wipe throws', () async {
      final st = InMemoryAppStorage();
      await st.plans.add(birdId: 'norcar', actions: [cand('a1')], now: t0);
      await st.settings.setAll({'a': '1'});
      st.failWipe = StateError('x');
      await expectLater(st.wipeAll(), throwsA(anything));
      expect(await st.plans.load(), hasLength(1));
      await st.wipeAll();
      expect(await st.plans.load(), isEmpty);
      expect(await st.settings.loadAll(), isEmpty);
    });
  });

  group('AudioCache.sweep', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('ecoyard_audio_'));
    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    File put(String name) =>
        File('${dir.path}/$name')..writeAsBytesSync([1, 2, 3]);

    test('removes leftover recordings and nothing else', () async {
      final ours = [
        put('ecoyard_1763100000000000.m4a'),
        put('ecoyard_5.m4a'),
      ];
      final others = [
        put('other_recording.m4a'),
        put('ecoyard_notes.txt'),
        put('ecoyard_abc.m4a'),
        put('my_ecoyard_5.m4a'),
        put('ecoyard_5.m4a.bak'),
      ];
      final n = await AudioCache(tempDir: () async => dir).sweep();
      expect(n, 2);
      for (final f in ours) {
        expect(f.existsSync(), isFalse, reason: f.path);
      }
      for (final f in others) {
        expect(f.existsSync(), isTrue, reason: f.path);
      }
    });

    test('does not touch folders, even ones named like a recording', () async {
      final d = Directory('${dir.path}/ecoyard_7.m4a')..createSync();
      File('${d.path}/inner.txt').writeAsStringSync('keep');
      expect(await AudioCache(tempDir: () async => dir).sweep(), 0);
      expect(d.existsSync(), isTrue);
      expect(File('${d.path}/inner.txt').existsSync(), isTrue);
    });

    test('an empty or missing folder is fine and returns 0', () async {
      expect(await AudioCache(tempDir: () async => dir).sweep(), 0);
      dir.deleteSync(recursive: true);
      expect(await AudioCache(tempDir: () async => dir).sweep(), 0);
    });

    test('a file-system error never throws', () async {
      expect(
        await AudioCache(tempDir: () async => throw StateError('no temp'))
            .sweep(),
        0,
      );
    });

    test('running it twice is harmless', () async {
      put('ecoyard_9.m4a');
      final c = AudioCache(tempDir: () async => dir);
      expect(await c.sweep(), 1);
      expect(await c.sweep(), 0);
    });
  });
}
