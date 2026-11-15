import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:sqflite/sqflite.dart';

import 'app_database.dart';
import 'migrations.dart';
import 'plan_store.dart';

/// The plan in a SQLite file in the app's private storage.
///
/// Failure policy: if the file cannot be opened or migrated, [open] throws
/// and the screen says so. Nothing here ever deletes or recreates the file to
/// "recover": an empty plan after an error would look like lost data.
class SqflitePlanStore implements PlanStore {
  /// [ownsDatabase]: whether [close] closes the database. False when the
  /// database is shared with other stores (see `SqliteAppStorage`).
  SqflitePlanStore.shared(this._db, {this.ownsDatabase = false});

  static const String fileName = 'ecoyard.db';

  final Database _db;
  final bool ownsDatabase;

  /// Opens (and migrates) the database for this store alone. Used by tests
  /// and by anything that only needs the plan.
  static Future<SqflitePlanStore> open({
    String? path,
    DatabaseFactory? factory,
    List<List<String>> migrations = planMigrations,
  }) async {
    final db = await openAppDatabase(
      path: path,
      factory: factory,
      migrations: migrations,
    );
    return SqflitePlanStore.shared(db, ownsDatabase: true);
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
  Future<void> close() async {
    if (ownsDatabase) await _db.close();
  }
}
