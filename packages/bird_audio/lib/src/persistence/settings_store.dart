/// Where the user's settings are kept, as text key/value pairs.
/// Screens depend on this, never on SQLite, so tests use
/// [InMemorySettingsStore].
abstract interface class SettingsStore {
  /// Every stored pair. Unknown keys are returned as they are; reading them
  /// into typed settings is `AppSettings.fromMap`'s job and it ignores what
  /// it does not know.
  Future<Map<String, String>> loadAll();

  /// Writes all [values] in one transaction (all or none).
  Future<void> setAll(Map<String, String> values);

  /// Deletes every stored setting.
  Future<void> clear();
}

class InMemorySettingsStore implements SettingsStore {
  InMemorySettingsStore([Map<String, String>? initial])
      : _values = {...?initial};

  final Map<String, String> _values;

  /// Set to make the next call fail, to test error states.
  Object? failNext;

  void _maybeFail() {
    final f = failNext;
    if (f != null) {
      failNext = null;
      throw f;
    }
  }

  @override
  Future<Map<String, String>> loadAll() async {
    _maybeFail();
    return {..._values};
  }

  @override
  Future<void> setAll(Map<String, String> values) async {
    _maybeFail();
    _values.addAll(values);
  }

  @override
  Future<void> clear() async {
    _maybeFail();
    _values.clear();
  }
}
