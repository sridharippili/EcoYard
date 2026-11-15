/// Numbered, append-only database migrations for the whole app database
/// (plan + settings). Named `planMigrations` since the plan came first.
///
/// Rules (CLAUDE.md rule 3):
/// - Never edit or reorder an existing entry once a build that contains it
///   has shipped. Add a new entry at the end.
/// - Entry N moves the database from version N-1 to N. The database version
///   equals the number of entries.
/// - Plain SQL types only (TEXT ISO-8601 dates, TEXT ids), so any SQLite
///   tool can read the file.
const List<List<String>> planMigrations = [
  // 1: the habitat plan.
  [
    '''
CREATE TABLE plan_actions (
  action_id TEXT NOT NULL PRIMARY KEY,
  added_at  TEXT NOT NULL,
  done_at   TEXT,
  title     TEXT NOT NULL,
  body      TEXT NOT NULL,
  cost      TEXT NOT NULL
)''',
    '''
CREATE TABLE plan_action_birds (
  action_id TEXT NOT NULL REFERENCES plan_actions(action_id) ON DELETE CASCADE,
  bird_id   TEXT NOT NULL,
  PRIMARY KEY (action_id, bird_id)
)''',
  ],
  // 2: the user's settings, as text key/value pairs. Added after the plan
  // tables shipped, so it is a new entry and migration 1 is untouched.
  [
    '''
CREATE TABLE IF NOT EXISTS settings (
  key   TEXT NOT NULL PRIMARY KEY,
  value TEXT NOT NULL
)''',
  ],
];
