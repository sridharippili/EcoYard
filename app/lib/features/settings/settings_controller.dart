import 'dart:async';
import 'dart:ui' show Rect;

import 'package:bird_audio/bird_audio.dart';
import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:flutter/foundation.dart';

import 'offline_model_controller.dart';

enum SettingsLoadState { loading, ready, failed }

/// The user's settings, and the data controls (see, copy, erase).
///
/// Owned by the Shell. Defaults are read when a screen starts (the Plants
/// filters, a new bird result), never pushed into a screen the user is
/// looking at.
class SettingsController extends ChangeNotifier {
  SettingsController({
    required this.storage,
    required this.audio,
    required this.now,
    required this.exporter,
    required this.reminders,
    required this.offline,
  });

  /// Opens the shared storage (or returns it if already open).
  final Future<AppStorage> Function() storage;
  final AudioCache audio;
  final DataExporter exporter;
  final ReminderScheduler reminders;
  final OfflineModelController offline;
  final DateTime Function() now;

  SettingsLoadState state = SettingsLoadState.loading;
  AppSettings settings = AppSettings.initial;

  /// Set when a save could not be written.
  String? saveError;

  bool _disposed = false;
  Future<void>? _starting;

  /// Loads the settings. A failure leaves [state] `failed` and the defaults
  /// in place: the app is still usable, and Settings says what went wrong.
  Future<void> init() =>
      _starting ??= _init().whenComplete(() => _starting = null);

  Future<void> _init() async {
    state = SettingsLoadState.loading;
    _notify();
    try {
      // A hung open must not keep the app on a spinner forever.
      final s = await storage().timeout(const Duration(seconds: 5));
      settings = AppSettings.fromMap(await s.settings.loadAll());
      state = SettingsLoadState.ready;
    } catch (_) {
      state = SettingsLoadState.failed;
    }
    _notify();
  }

  /// Saves the starting choices. Keeps the old value on screen if the write
  /// fails. Saves run one after another, so two quick taps never overwrite
  /// each other.
  Future<bool> saveDefaults({
    SpaceType? space,
    SunExposure? sun,
    BudgetTier? budget,
  }) => _save(
    (s) =>
        s.copyWith(defaultSpace: space, defaultSun: sun, defaultBudget: budget),
  );

  /// Saves the place the weather is for. Passing no place forgets it.
  Future<bool> savePlace({Place? place, bool? useDeviceLocation}) => _save(
    (s) => s.copyWith(
      place: place,
      clearPlace: place == null,
      useDeviceLocation: useDeviceLocation,
    ),
  );

  /// Saves the weekly reminder switch and/or its day and time.
  Future<bool> saveReminder({bool? on, ReminderTime? time}) =>
      _save((s) => s.copyWith(reminderOn: on, reminderTime: time));

  /// The introduction was seen or skipped.
  Future<bool> markOnboarded() =>
      _save((s) => s.copyWith(onboardingDone: true));

  Future<void> _saveQueue = Future<void>.value();

  Future<bool> _save(AppSettings Function(AppSettings current) change) {
    final run = _saveQueue.then((_) => _saveNow(change));
    _saveQueue = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  Future<bool> _saveNow(AppSettings Function(AppSettings) change) async {
    // If the stored settings could not be read, do not write over them with
    // defaults: read them first, and refuse to save if that still fails.
    if (state == SettingsLoadState.failed) {
      await init();
      if (state == SettingsLoadState.failed) {
        saveError = "Couldn't save that. Your choice was not changed.";
        _notify();
        return false;
      }
    }
    final next = change(settings); // from the latest, not from a stale copy
    try {
      final s = await storage();
      await s.settings.setAll(next.toMap());
      settings = next;
      saveError = null;
      _notify();
      return true;
    } catch (_) {
      saveError = "Couldn't save that. Your choice was not changed.";
      _notify();
      return false;
    }
  }

  /// Counts of what is really stored. Throws if the storage cannot be read.
  Future<DataSummary> summary() async {
    final s = await storage();
    return DataSummary.of(await s.plans.load(), await s.settings.loadAll());
  }

  /// Everything stored, as JSON text. Throws if the storage cannot be read.
  Future<String> exportText() async {
    final s = await storage();
    return exportMyData(
      plan: await s.plans.load(),
      settings: AppSettings.fromMap(await s.settings.loadAll()),
      exportedOn: now(),
    );
  }

  /// Offers everything stored as a JSON file in the share sheet. Throws if
  /// the storage cannot be read (nothing is shared in that case).
  Future<ExportOutcome> exportFile({Rect? origin}) async {
    final text = await exportText();
    return exporter.export(text, origin: origin);
  }

  /// Erases the plan and the settings in one step, then any recording a crash
  /// left behind. Throws (and changes nothing) if the erase failed.
  ///
  /// After this the app is back to a first launch: defaults, introduction not
  /// seen. The caller resets the screens that hold copies of the data.
  Future<void> deleteEverything() async {
    // No download may be running, and the model must be closed, while the
    // data is erased.
    await offline.stopForErase();
    final s = await storage();
    await s.wipeAll();
    settings = AppSettings.initial;
    saveError = null;
    state = SettingsLoadState.ready;
    _notify();
    await audio.sweep();
    // A leftover export file holds the data that was just erased.
    await exporter.sweep();
    // The downloaded model and any partial file go too.
    await offline.eraseAfterWipe();
    // The settings are back to "reminder off"; no notification may remain.
    try {
      await reminders.cancelAll();
    } catch (_) {}
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
