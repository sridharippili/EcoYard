import 'dart:convert';

import 'habitat_engine.dart' show BudgetTier;
import 'weather.dart';
import 'models.dart';
import 'plan.dart';

/// The few things the user can choose in Settings. Plain values only.
///
/// Stored as text key/value pairs, so a missing, unknown or corrupted entry
/// must never crash the app: [AppSettings.fromMap] falls back to the default
/// for anything it does not understand.
class AppSettings {
  const AppSettings({
    this.defaultSpace = SpaceType.yard,
    this.defaultSun = SunExposure.full,
    this.defaultBudget = BudgetTier.any,
    this.onboardingDone = false,
    this.place,
    this.useDeviceLocation = false,
  });

  /// What a fresh install, or a wiped one, starts with.
  static const AppSettings initial = AppSettings();

  /// The starting choices for the Plant Finder and the bird advice.
  final SpaceType defaultSpace;
  final SunExposure defaultSun;
  final BudgetTier defaultBudget;

  /// Whether the 3-screen introduction has been seen or skipped.
  final bool onboardingDone;

  /// The place the weather is for, or null when the user has not chosen one
  /// and has not allowed location. Always coarse (see [Place.coarse]).
  final Place? place;

  /// Whether the user let EcoYard use the device's approximate location.
  /// False until they say yes; never assumed.
  final bool useDeviceLocation;

  static const keySpace = 'defaultSpace';
  static const keySun = 'defaultSun';
  static const keyBudget = 'defaultBudget';
  static const keyOnboarded = 'onboardingDone';
  static const keyPlaceName = 'placeName';
  static const keyPlaceAdmin = 'placeAdmin';
  static const keyPlaceLat = 'placeLat';
  static const keyPlaceLon = 'placeLon';
  static const keyUseDeviceLocation = 'useDeviceLocation';

  /// Reads settings from stored text. Anything unknown gets its default.
  factory AppSettings.fromMap(Map<String, String> m) {
    T pick<T>(List<T> values, String? stored, String Function(T) json, T def) {
      for (final v in values) {
        if (json(v) == stored) return v;
      }
      return def;
    }

    return AppSettings(
      defaultSpace: pick(
        SpaceType.values,
        m[keySpace],
        (e) => e.json,
        initial.defaultSpace,
      ),
      defaultSun: pick(
        SunExposure.values,
        m[keySun],
        (e) => e.json,
        initial.defaultSun,
      ),
      defaultBudget: pick(
        BudgetTier.values,
        m[keyBudget],
        (e) => e.json,
        initial.defaultBudget,
      ),
      onboardingDone: m[keyOnboarded] == 'true',
      place: Place.fromMap({
        if (m[keyPlaceName] != null) 'name': m[keyPlaceName]!,
        if (m[keyPlaceAdmin] != null) 'admin': m[keyPlaceAdmin]!,
        if (m[keyPlaceLat] != null) 'lat': m[keyPlaceLat]!,
        if (m[keyPlaceLon] != null) 'lon': m[keyPlaceLon]!,
      }),
      useDeviceLocation: m[keyUseDeviceLocation] == 'true',
    );
  }

  Map<String, String> toMap() => {
        keySpace: defaultSpace.json,
        keySun: defaultSun.json,
        keyBudget: defaultBudget.json,
        keyOnboarded: onboardingDone.toString(),
        keyUseDeviceLocation: useDeviceLocation.toString(),
        // Every key is always written, blank when there is no place: a store
        // that merges writes would otherwise keep an old place for ever.
        keyPlaceName: place?.name ?? '',
        keyPlaceAdmin: place?.admin ?? '',
        keyPlaceLat: place?.latitude.toString() ?? '',
        keyPlaceLon: place?.longitude.toString() ?? '',
      };

  AppSettings copyWith({
    SpaceType? defaultSpace,
    SunExposure? defaultSun,
    BudgetTier? defaultBudget,
    bool? onboardingDone,
    Place? place,
    bool clearPlace = false,
    bool? useDeviceLocation,
  }) =>
      AppSettings(
        defaultSpace: defaultSpace ?? this.defaultSpace,
        defaultSun: defaultSun ?? this.defaultSun,
        defaultBudget: defaultBudget ?? this.defaultBudget,
        onboardingDone: onboardingDone ?? this.onboardingDone,
        place: clearPlace ? null : (place ?? this.place),
        useDeviceLocation: useDeviceLocation ?? this.useDeviceLocation,
      );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.defaultSpace == defaultSpace &&
      other.defaultSun == defaultSun &&
      other.defaultBudget == defaultBudget &&
      other.onboardingDone == onboardingDone &&
      other.place == place &&
      other.useDeviceLocation == useDeviceLocation;

  @override
  int get hashCode => Object.hash(defaultSpace, defaultSun, defaultBudget,
      onboardingDone, place, useDeviceLocation);
}

/// What "Manage my data" shows, counted from what is really stored.
class DataSummary {
  const DataSummary({
    required this.planActions,
    required this.birdsInPlan,
    required this.settingsStored,
  });

  factory DataSummary.of(List<PlanEntry> plan, Map<String, String> settings) =>
      DataSummary(
        planActions: plan.length,
        birdsInPlan: {for (final e in plan) ...e.birdIds}.length,
        settingsStored: settings.length,
      );

  final int planActions;

  /// Different birds the plan was built for.
  final int birdsInPlan;

  /// Number of saved settings values.
  final int settingsStored;

  bool get isEmpty =>
      planActions == 0 && birdsInPlan == 0 && settingsStored == 0;
}

/// Everything EcoYard stores about the user, as JSON text they can copy.
///
/// Pure: [exportedOn] is passed in. Lists only what is really stored (the
/// plan and the settings) and says what EcoYard does not keep on the device.
String exportMyData({
  required List<PlanEntry> plan,
  required AppSettings settings,
  required DateTime exportedOn,
}) {
  final sorted = [...plan]..sort((a, b) => a.addedOn.compareTo(b.addedOn));
  final data = <String, Object?>{
    'app': 'EcoYard',
    'exportedOn': exportedOn.toUtc().toIso8601String(),
    'plan': [
      for (final e in sorted)
        {
          'actionId': e.actionId,
          'title': e.titleSnapshot,
          'birdIds': e.birdIds,
          'addedOn': e.addedOn,
          'doneOn': e.doneOn,
        },
    ],
    'settings': settings.toMap(),
    'notKeptOnThisDevice': ['audio recordings', 'location'],
  };
  return const JsonEncoder.withIndent('  ').convert(data);
}
