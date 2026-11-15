import 'dart:io';

import 'package:bird_audio/bird_audio.dart';
import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

PlanCandidate cand(String id, {String title = 'Title'}) => PlanCandidate(
      actionId: id,
      title: '$title $id',
      body: 'Body $id',
      costTier: CostTier.free,
    );

final t0 = DateTime.utc(2026, 11, 14, 10);
final t1 = DateTime.utc(2026, 11, 15, 10);
final t2 = DateTime.utc(2026, 11, 16, 10);

/// Rules every store must obey, run against memory and SQLite alike.
void storeContract(Future<PlanStore> Function() create) {
  late PlanStore s;
  setUp(() async => s = await create());
  tearDown(() => s.close());

  PlanEntry only(List<PlanEntry> l, String id) =>
      l.singleWhere((e) => e.actionId == id);

  test('starts empty', () async {
    expect(await s.load(), isEmpty);
  });

  test('add stores a snapshot, the bird and a UTC timestamp', () async {
    final r = await s.add(birdId: 'norcar', actions: [cand('a1')], now: t0);
    expect(r.added, ['a1']);
    expect(r.alreadyInPlan, isEmpty);
    final e = only(await s.load(), 'a1');
    expect(e.birdIds, ['norcar']);
    expect(e.titleSnapshot, 'Title a1');
    expect(e.bodySnapshot, 'Body a1');
    expect(e.costSnapshot, 'free');
    expect(e.addedOn, '2026-11-14T10:00:00.000Z');
    expect(e.isDone, isFalse);
  });

  test('a local time is stored as UTC', () async {
    final local = DateTime(2026, 11, 14, 10); // this machine's time zone
    expect(local.isUtc, isFalse);
    await s.add(birdId: 'norcar', actions: [cand('a1')], now: local);
    final stored = only(await s.load(), 'a1').addedOn;
    expect(stored, endsWith('Z'));
    expect(stored, local.toUtc().toIso8601String());
  });

  test('same action for a second bird merges into one item', () async {
    await s.add(birdId: 'norcar', actions: [cand('a1')], now: t0);
    final r = await s.add(birdId: 'amegfi', actions: [cand('a1')], now: t1);
    expect(r.added, isEmpty);
    expect(r.alreadyInPlan, ['a1']);
    final all = await s.load();
    expect(all, hasLength(1));
    expect(all.single.birdIds, ['norcar', 'amegfi']);
  });

  test('a second bird does not reset added date or snapshot', () async {
    await s.add(birdId: 'norcar', actions: [cand('a1')], now: t0);
    await s.add(birdId: 'amegfi', actions: [cand('a1', title: 'New')], now: t1);
    final e = only(await s.load(), 'a1');
    expect(e.addedOn, t0.toIso8601String());
    expect(e.titleSnapshot, 'Title a1');
  });

  test('same action and same bird twice stores one bird row', () async {
    await s.add(birdId: 'norcar', actions: [cand('a1')], now: t0);
    final r = await s.add(birdId: 'norcar', actions: [cand('a1')], now: t1);
    expect(r.alreadyInPlan, ['a1']);
    expect(only(await s.load(), 'a1').birdIds, ['norcar']);
  });

  test('re-adding a done action keeps it done and adds the bird', () async {
    await s.add(birdId: 'norcar', actions: [cand('a1')], now: t0);
    await s.setDone('a1', done: true, now: t1);
    await s.add(birdId: 'amegfi', actions: [cand('a1')], now: t2);
    final e = only(await s.load(), 'a1');
    expect(e.isDone, isTrue);
    expect(e.doneOn, t1.toIso8601String());
    expect(e.birdIds, ['norcar', 'amegfi']);
  });

  test('banner numbers count only new actions', () async {
    await s.add(birdId: 'norcar', actions: [cand('a1')], now: t0);
    final r = await s.add(
      birdId: 'amegfi',
      actions: [cand('a1'), cand('a2'), cand('a3')],
      now: t1,
    );
    expect(r.added, ['a2', 'a3']);
    expect(r.alreadyInPlan, ['a1']);
  });

  test('setDone ticks, un-ticks, and ignores unknown ids', () async {
    await s.add(birdId: 'norcar', actions: [cand('a1')], now: t0);
    await s.setDone('a1', done: true, now: t1);
    expect(only(await s.load(), 'a1').doneOn, t1.toIso8601String());
    await s.setDone('a1', done: false, now: t2);
    expect(only(await s.load(), 'a1').doneOn, isNull);
    await s.setDone('nope', done: true, now: t2);
    expect(await s.load(), hasLength(1));
  });

  test('remove deletes one action and keeps the rest', () async {
    await s.add(birdId: 'norcar', actions: [cand('a1'), cand('a2')], now: t0);
    await s.remove('a1');
    expect((await s.load()).map((e) => e.actionId), ['a2']);
    await s.add(birdId: 'norcar', actions: [cand('a1')], now: t1);
    expect(only(await s.load(), 'a1').birdIds, ['norcar']);
  });

  group('edge cases', () {
    test('actions added together keep the order they were chosen in', () async {
      await s.add(
        birdId: 'norcar',
        actions: [cand('zeta'), cand('alpha'), cand('mid')],
        now: t0,
      );
      final all = await s.load()
        ..sort((a, b) => a.addedOn.compareTo(b.addedOn));
      expect(all.map((e) => e.actionId), ['zeta', 'alpha', 'mid']);
      expect(all.map((e) => e.addedOn).toSet(), hasLength(3));
      expect(all.first.addedOn, t0.toIso8601String());
    });

    test('adding an empty list is a no-op', () async {
      final r = await s.add(birdId: 'norcar', actions: [], now: t0);
      expect(r.added, isEmpty);
      expect(r.alreadyInPlan, isEmpty);
      expect(await s.load(), isEmpty);
    });

    test('the same action twice in one call counts once', () async {
      final r = await s.add(
        birdId: 'norcar',
        actions: [cand('a1'), cand('a1')],
        now: t0,
      );
      expect(r.added, ['a1']);
      expect(r.alreadyInPlan, isEmpty);
      final all = await s.load();
      expect(all, hasLength(1));
      expect(all.single.birdIds, ['norcar']);
    });

    test('removing an unknown id changes nothing', () async {
      await s.add(birdId: 'norcar', actions: [cand('a1')], now: t0);
      await s.remove('nope');
      expect(await s.load(), hasLength(1));
    });

    test('remove then re-add starts fresh: new date, only the new bird',
        () async {
      await s.add(birdId: 'norcar', actions: [cand('a1')], now: t0);
      await s.setDone('a1', done: true, now: t1);
      await s.remove('a1');
      await s.add(birdId: 'amegfi', actions: [cand('a1')], now: t2);
      final e = only(await s.load(), 'a1');
      expect(e.birdIds, ['amegfi']);
      expect(e.addedOn, t2.toIso8601String());
      expect(e.isDone, isFalse);
    });

    test('clear then add works', () async {
      await s.add(birdId: 'norcar', actions: [cand('a1')], now: t0);
      await s.clear();
      await s.add(birdId: 'norcar', actions: [cand('a1')], now: t1);
      expect(only(await s.load(), 'a1').addedOn, t1.toIso8601String());
    });

    test('clear on an empty plan is fine', () async {
      await s.clear();
      expect(await s.load(), isEmpty);
    });

    test('un-ticking an open item and ticking twice are harmless', () async {
      await s.add(birdId: 'norcar', actions: [cand('a1')], now: t0);
      await s.setDone('a1', done: false, now: t1);
      expect(only(await s.load(), 'a1').isDone, isFalse);
      await s.setDone('a1', done: true, now: t1);
      await s.setDone('a1', done: true, now: t2);
      expect(only(await s.load(), 'a1').isDone, isTrue);
    });

    test('quotes, SQL text and emoji round-trip untouched', () async {
      const evil = "x'; DROP TABLE plan_actions; -- \u{1F426}";
      await s.add(
        birdId: evil,
        actions: [
          PlanCandidate(
            actionId: evil,
            title: evil,
            body: 'Line one\nLine two, "quoted"',
            costTier: CostTier.low,
          ),
        ],
        now: t0,
      );
      final e = only(await s.load(), evil);
      expect(e.birdIds, [evil]);
      expect(e.titleSnapshot, evil);
      expect(e.bodySnapshot, 'Line one\nLine two, "quoted"');
      expect(e.costSnapshot, 'low');
      expect(await s.load(), hasLength(1)); // the table still exists
    });

    test('a very long body is stored whole', () async {
      final long = 'word ' * 20000;
      await s.add(
        birdId: 'norcar',
        actions: [
          PlanCandidate(
            actionId: 'a1',
            title: 't',
            body: long,
            costTier: CostTier.free,
          ),
        ],
        now: t0,
      );
      expect(only(await s.load(), 'a1').bodySnapshot, long);
    });

    test('many items and many birds keep their order', () async {
      for (var i = 0; i < 120; i++) {
        await s.add(
          birdId: 'b${i % 7}',
          actions: [cand('act-${i.toString().padLeft(3, '0')}')],
          now: t0.add(Duration(minutes: i)),
        );
      }
      final all = await s.load();
      expect(all, hasLength(120));
      await s.add(birdId: 'z1', actions: [cand('act-005')], now: t2);
      await s.add(birdId: 'z2', actions: [cand('act-005')], now: t2);
      expect(only(await s.load(), 'act-005').birdIds, ['b5', 'z1', 'z2']);
    });

    test('two adds started together both land', () async {
      final r = await Future.wait([
        s.add(birdId: 'norcar', actions: [cand('a1'), cand('a2')], now: t0),
        s.add(birdId: 'amegfi', actions: [cand('a2'), cand('a3')], now: t0),
      ]);
      final all = await s.load();
      expect(all.map((e) => e.actionId).toSet(), {'a1', 'a2', 'a3'});
      expect(only(all, 'a2').birdIds.toSet(), {'norcar', 'amegfi'});
      // Exactly one of the two calls created a2.
      final createdA2 = r.where((x) => x.added.contains('a2')).length;
      expect(createdA2, 1);
    });

    test('an empty bird id or empty text is not silently dropped', () async {
      await s.add(
        birdId: '',
        actions: [
          const PlanCandidate(
            actionId: 'a1',
            title: '',
            body: '',
            costTier: CostTier.free,
          ),
        ],
        now: t0,
      );
      final e = only(await s.load(), 'a1');
      expect(e.birdIds, ['']);
      expect(e.titleSnapshot, '');
    });
  });

  test('clear empties the plan', () async {
    await s.add(birdId: 'norcar', actions: [cand('a1'), cand('a2')], now: t0);
    await s.clear();
    expect(await s.load(), isEmpty);
  });
}

void main() {
  sqfliteFfiInit();
  late Directory tmp;
  var n = 0;

  setUpAll(() => tmp = Directory.systemTemp.createTempSync('ecoyard_plan_'));
  tearDownAll(() => tmp.deleteSync(recursive: true));

  String dbPath() => '${tmp.path}/db_${n++}.db';

  group('InMemoryPlanStore', () {
    storeContract(() async => InMemoryPlanStore());
  });

  group('SqflitePlanStore', () {
    storeContract(
      () => SqflitePlanStore.open(path: dbPath(), factory: databaseFactoryFfi),
    );

    test('using a closed store fails loudly, it never pretends', () async {
      final s = await SqflitePlanStore.open(
        path: dbPath(),
        factory: databaseFactoryFfi,
      );
      await s.close();
      await expectLater(s.load(), throwsA(anything));
      await expectLater(
        s.add(birdId: 'norcar', actions: [cand('a1')], now: t0),
        throwsA(anything),
      );
    });

    test('removing an action also removes its bird rows (no orphans)',
        () async {
      final path = dbPath();
      final s = await SqflitePlanStore.open(
        path: path,
        factory: databaseFactoryFfi,
      );
      await s.add(birdId: 'norcar', actions: [cand('a1')], now: t0);
      await s.remove('a1');
      await s.add(birdId: 'amegfi', actions: [cand('a2')], now: t1);
      await s.clear();
      final raw = await databaseFactoryFfi.openDatabase(path);
      expect(await raw.query('plan_action_birds'), isEmpty);
      expect(await raw.query('plan_actions'), isEmpty);
      await s.close();
    });

    test('a failure part-way through add leaves nothing half-written',
        () async {
      final path = dbPath();
      final s =
          await SqflitePlanStore.open(path: path, factory: databaseFactoryFfi);
      // A second connection adds a trap: inserting a bird row for "boom"
      // fails, after the first action was already written in the transaction.
      final raw = await databaseFactoryFfi.openDatabase(path);
      await raw.execute('''
CREATE TRIGGER trap BEFORE INSERT ON plan_action_birds
WHEN NEW.action_id = 'boom'
BEGIN SELECT RAISE(ABORT, 'trap'); END''');
      // Not closed: sqflite shares one connection per path, so closing it
      // would close the store's too.
      expect(raw, isNotNull);

      await expectLater(
        s.add(birdId: 'norcar', actions: [cand('a1'), cand('boom')], now: t0),
        throwsA(anything),
      );
      expect(await s.load(), isEmpty);
      await s.close();
    });

    test('data survives closing and reopening the file', () async {
      final path = dbPath();
      var s =
          await SqflitePlanStore.open(path: path, factory: databaseFactoryFfi);
      await s.add(birdId: 'norcar', actions: [cand('a1')], now: t0);
      await s.setDone('a1', done: true, now: t1);
      await s.close();
      s = await SqflitePlanStore.open(path: path, factory: databaseFactoryFfi);
      final e = (await s.load()).single;
      expect(e.actionId, 'a1');
      expect(e.isDone, isTrue);
      await s.close();
    });

    test('a further migration appended later keeps the saved plan', () async {
      final path = dbPath();
      var s =
          await SqflitePlanStore.open(path: path, factory: databaseFactoryFfi);
      await s.add(birdId: 'norcar', actions: [cand('a1')], now: t0);
      await s.close();

      final v2 = [
        ...planMigrations,
        ['ALTER TABLE plan_actions ADD COLUMN note TEXT'],
      ];
      s = await SqflitePlanStore.open(
        path: path,
        factory: databaseFactoryFfi,
        migrations: v2,
      );
      expect((await s.load()).single.actionId, 'a1');
      await s.close();

      final raw = await databaseFactoryFfi.openDatabase(path);
      expect(await raw.getVersion(), planMigrations.length + 1);
      await raw.close();
    });

    test(
        'a real v1 plan database migrates to the settings schema (v2) and '
        'keeps every row', () async {
      final path = dbPath();
      // Exactly what shipped in Phase 4: only the first migration.
      var s = await SqflitePlanStore.open(
        path: path,
        factory: databaseFactoryFfi,
        migrations: [planMigrations.first],
      );
      await s.add(
        birdId: 'norcar',
        actions: [cand('a1'), cand('a2')],
        now: t0,
      );
      await s.setDone('a1', done: true, now: t1);
      await s.add(birdId: 'amegfi', actions: [cand('a1')], now: t2);
      await s.close();

      var raw = await databaseFactoryFfi.openDatabase(path);
      expect(await raw.getVersion(), 1);
      await raw.close();

      s = await SqflitePlanStore.open(path: path, factory: databaseFactoryFfi);
      final all = await s.load();
      expect(all.map((e) => e.actionId).toSet(), {'a1', 'a2'});
      final a1 = all.singleWhere((e) => e.actionId == 'a1');
      expect(a1.birdIds, ['norcar', 'amegfi']);
      expect(a1.isDone, isTrue);
      await s.close();

      raw = await databaseFactoryFfi.openDatabase(path);
      expect(await raw.getVersion(), 2);
      final tables = (await raw.rawQuery(
        "select name from sqlite_master where type='table'",
      ))
          .map((r) => r['name'])
          .toSet();
      expect(tables,
          containsAll(['plan_actions', 'plan_action_birds', 'settings']));
      await raw.close();
    });

    test('the version equals the number of migrations', () async {
      final path = dbPath();
      final s =
          await SqflitePlanStore.open(path: path, factory: databaseFactoryFfi);
      await s.close();
      final raw = await databaseFactoryFfi.openDatabase(path);
      expect(await raw.getVersion(), planMigrations.length);
      await raw.close();
    });

    test('a database from a newer app is refused, not wiped', () async {
      final path = dbPath();
      var s = await SqflitePlanStore.open(
        path: path,
        factory: databaseFactoryFfi,
        migrations: [
          ...planMigrations,
          ['ALTER TABLE plan_actions ADD COLUMN note TEXT'],
        ],
      );
      await s.add(birdId: 'norcar', actions: [cand('a1')], now: t0);
      await s.close();

      await expectLater(
        SqflitePlanStore.open(path: path, factory: databaseFactoryFfi),
        throwsA(anything),
      );
      // Still there for the newer app.
      s = await SqflitePlanStore.open(
        path: path,
        factory: databaseFactoryFfi,
        migrations: [
          ...planMigrations,
          ['ALTER TABLE plan_actions ADD COLUMN note TEXT'],
        ],
      );
      expect((await s.load()).single.actionId, 'a1');
      await s.close();
    });
  });
}
