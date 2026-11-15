import 'package:sqflite/sqflite.dart';

import 'app_database.dart';
import 'migrations.dart';
import 'plan_store.dart';
import 'settings_store.dart';
import 'sqflite_plan_store.dart';
import 'sqflite_settings_store.dart';

/// Everything the app stores about the user, opened once.
abstract interface class AppStorage {
  PlanStore get plans;
  SettingsStore get settings;

  /// Erases the plan AND the settings together: either both go or neither.
  /// Throws if it could not, so the caller never reports an erase that did
  /// not happen.
  Future<void> wipeAll();

  Future<void> close();
}

/// In memory, for tests and previews. Same rules as SQLite.
class InMemoryAppStorage implements AppStorage {
  InMemoryAppStorage({PlanStore? plans, SettingsStore? settings})
      : plans = plans ?? InMemoryPlanStore(),
        settings = settings ?? InMemorySettingsStore();

  @override
  final PlanStore plans;
  @override
  final SettingsStore settings;

  /// Set to make the next [wipeAll] fail.
  Object? failWipe;

  @override
  Future<void> wipeAll() async {
    final f = failWipe;
    if (f != null) {
      failWipe = null;
      throw f;
    }
    await plans.clear();
    await settings.clear();
  }

  @override
  Future<void> close() async {}
}

/// The real thing: one SQLite file shared by the plan and the settings.
class SqliteAppStorage implements AppStorage {
  SqliteAppStorage._(this._db)
      : plans = SqflitePlanStore.shared(_db),
        settings = SqfliteSettingsStore(_db);

  final Database _db;

  @override
  final PlanStore plans;
  @override
  final SettingsStore settings;

  static Future<SqliteAppStorage> open({
    String? path,
    DatabaseFactory? factory,
    List<List<String>> migrations = planMigrations,
  }) async =>
      SqliteAppStorage._(
        await openAppDatabase(
            path: path, factory: factory, migrations: migrations),
      );

  @override
  Future<void> wipeAll() async {
    await _db.transaction((txn) async {
      await txn.delete('plan_actions'); // plan_action_birds cascades
      await txn.delete('settings');
    });
    // Give the freed pages back and drop the old content from the file.
    // Best effort: the erase has already committed, so a VACUUM problem (for
    // example low disk space) must not turn a successful erase into a
    // reported failure. (An earlier iCloud backup may still hold older
    // copies: that is outside the app and is never claimed to be erased.)
    try {
      await _db.execute('VACUUM');
    } catch (_) {}
  }

  @override
  Future<void> close() => _db.close();
}
