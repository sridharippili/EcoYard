import 'package:sqflite/sqflite.dart';

import 'settings_store.dart';

/// Settings in the `settings` table of the app database.
class SqfliteSettingsStore implements SettingsStore {
  SqfliteSettingsStore(this._db);

  final Database _db;

  @override
  Future<Map<String, String>> loadAll() async {
    final rows = await _db.query('settings');
    return {
      for (final r in rows) r['key']! as String: r['value']! as String,
    };
  }

  @override
  Future<void> setAll(Map<String, String> values) async {
    await _db.transaction((txn) async {
      for (final e in values.entries) {
        await txn.insert(
          'settings',
          {'key': e.key, 'value': e.value},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  @override
  Future<void> clear() async {
    await _db.delete('settings');
  }
}
