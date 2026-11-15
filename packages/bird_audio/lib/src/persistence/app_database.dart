import 'package:sqflite/sqflite.dart';

import 'migrations.dart';

/// Opens (and migrates) the one SQLite file the app uses.
///
/// Failure policy: if the file cannot be opened or migrated this throws, and
/// the screens say so. Nothing here ever deletes or recreates the file to
/// "recover": an empty plan after an error would look like lost data. A file
/// written by a NEWER app version is refused, not wiped.
Future<Database> openAppDatabase({
  String? path,
  DatabaseFactory? factory,
  List<List<String>> migrations = planMigrations,
}) async {
  final f = factory ?? databaseFactory;
  final dbPath = path ?? '${await f.getDatabasesPath()}/ecoyard.db';
  return f.openDatabase(
    dbPath,
    options: OpenDatabaseOptions(
      version: migrations.length,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) => _migrate(db, 0, version, migrations),
      onUpgrade: (db, from, to) => _migrate(db, from, to, migrations),
      onDowngrade: (db, from, to) => throw StateError(
        'The saved data was written by a newer version of EcoYard '
        '(database v$from, this app understands v$to).',
      ),
    ),
  );
}

Future<void> _migrate(
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
