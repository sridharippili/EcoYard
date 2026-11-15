import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:sqflite/sqflite.dart';

import 'migrations.dart';
import 'plan_store.dart';

/// The plan in a SQLite file in the app's private storage.
///
/// Failure policy: if the file cannot be opened or migrated, [open] throws
/// and the screen says so. Nothing here ever deletes or recreates the file to
/// "recover": an empty plan after an error would look like lost data.
class SqflitePlanStore implements PlanStore {
  SqflitePlanStore._(this._db);

  static const String fileName = 'ecoyard.db';

  final Database _db;

  /// Opens (and migrates) the database. [path] defaults to the app's
  /// databases folder; tests pass a temp file and a ffi [factory].
  static Future<SqflitePlanStore> open({
    String? path,
    DatabaseFactory? factory,
    List<List<String>> migrations = planMigrations,
  }) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? '${await f.getDatabasesPath()}/$fileName';
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: migrations.length,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) => _migrate(db, 0, version, migrations),
        onUpgrade: (db, from, to) => _migrate(db, from, to, migrations),
        onDowngrade: (db, from, to) => throw StateError(
          'The saved plan was written by a newer version of EcoYard '
          '(database v$from, this app understands v$to).',
        ),
      ),
    );
    return SqflitePlanStore._(db);
  }

  static Future<void> _migrate(
    Database db,
    int from,
    int to,
    List<List<String>> migrations,
  ) async {
    for (var v = from; v < to; v++) {
      for (final sql in migrations[v]) {
        await db.execute(sql);
      }
    }
  }

  @override
  Future<List<PlanEntry>> load() async => _db.transaction((txn) async {
        // One transaction, so a write cannot land between the two queries and
        // leave an action without its birds.
        final actions = await txn.query('plan_actions');
        final birds = await txn.query('plan_action_birds', orderBy: 'rowid');
        final byAction = <String, List<String>>{};
        for (final r in birds) {
          (byAction[r['action_id']! as String] ??= [])
              .add(r['bird_id']! as String);
        }
        return [
          for (final r in actions)
            PlanEntry(
              actionId: r['action_id']! as String,
              birdIds: byAction[r['action_id']! as String] ?? const [],
              addedOn: r['added_at']! as String,
              doneOn: r['done_at'] as String?,
              titleSnapshot: r['title']! as String,
              bodySnapshot: r['body']! as String,
              costSnapshot: r['cost']! as String,
            ),
        ];
      });

  @override
  Future<PlanAddResult> add({
    required String birdId,
    required List<PlanCandidate> actions,
    required DateTime now,
  }) async {
    final unique = uniqueCandidates(actions);
    return _db.transaction((txn) async {
      final added = <String>[];
      final already = <String>[];
      for (var i = 0; i < unique.length; i++) {
        final a = unique[i];
        // Each action gets its own instant, so the order they were chosen in
        // is the order they are shown in.
        final stamp = stampFor(now, i);
        final exists = (await txn.query(
          'plan_actions',
          columns: ['action_id'],
          where: 'action_id = ?',
          whereArgs: [a.actionId],
        ))
            .isNotEmpty;
        if (exists) {
          already.add(a.actionId);
        } else {
          await txn.insert('plan_actions', {
            'action_id': a.actionId,
            'added_at': stamp,
            'title': a.title,
            'body': a.body,
            'cost': a.costTier.json,
          });
          added.add(a.actionId);
        }
        await txn.insert(
          'plan_action_birds',
          {'action_id': a.actionId, 'bird_id': birdId},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      return PlanAddResult(added: added, alreadyInPlan: already);
    });
  }

  @override
  Future<void> setDone(
    String actionId, {
    required bool done,
    required DateTime now,
  }) async {
    await _db.update(
      'plan_actions',
      {'done_at': done ? stampFor(now) : null},
      where: 'action_id = ?',
      whereArgs: [actionId],
    );
  }

  @override
  Future<void> remove(String actionId) async {
    await _db.delete(
      'plan_actions',
      where: 'action_id = ?',
      whereArgs: [actionId],
    );
  }

  @override
  Future<void> clear() async {
    await _db.delete('plan_actions');
  }

  @override
  Future<void> close() => _db.close();
}
