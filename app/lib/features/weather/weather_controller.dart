import 'dart:async';

import 'package:bird_audio/bird_audio.dart';
import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:flutter/foundation.dart';

enum WeatherState {
  /// No place chosen and location not allowed: nothing to show yet.
  noPlace,
  loading,
  ready,
  failed,
}

/// The Home weather card.
///
/// It only ever asks for the weather when the user has given a place, either
/// by typing one or by allowing their approximate location. Nothing is
/// fetched before that, and only a coarse position is ever sent.
class WeatherController extends ChangeNotifier {
  WeatherController({
    required this.service,
    required this.location,
    required this.now,
    required this.readPlace,
    required this.savePlace,
  });

  final WeatherService service;
  final DeviceLocation location;
  final DateTime Function() now;

  /// The saved place and whether location is allowed, read from settings.
  AppSettings Function() readPlace;

  /// Persists a chosen place (and whether it came from the device).
  final Future<bool> Function({Place? place, bool? useDeviceLocation})
  savePlace;

  WeatherState state = WeatherState.noPlace;
  WeatherNow? weather;
  Place? place;

  /// A sentence for the card when [state] is `failed`.
  String? error;

  bool _disposed = false;
  Future<void>? _inFlight;

  /// Loads the weather if we have a place and the last reading is old.
  /// Safe to call on every build: it does nothing when nothing is needed.
  Future<void> refreshIfNeeded() {
    final saved = readPlace().place;
    if (saved == null) {
      if (state != WeatherState.noPlace) {
        state = WeatherState.noPlace;
        weather = null;
        _notify();
      }
      return Future.value();
    }
    final current = weather;
    final samePlace = place == saved;
    if (samePlace &&
        current != null &&
        !weatherIsStale(current.observedAt, now())) {
      return Future.value();
    }
    return refresh(saved);
  }

  /// Fetches the weather for [forPlace] (or the saved place).
  Future<void> refresh([Place? forPlace]) {
    final target = forPlace ?? readPlace().place;
    if (target == null) return Future.value();
    return _inFlight ??= _refresh(target).whenComplete(() => _inFlight = null);
  }

  Future<void> _refresh(Place target) async {
    place = target;
    state = WeatherState.loading;
    error = null;
    _notify();
    try {
      weather = await service.forPlace(target);
      state = WeatherState.ready;
    } on WeatherUnavailable catch (e) {
      error = e.message;
      state = WeatherState.failed;
    } catch (_) {
      error = 'The weather could not be loaded.';
      state = WeatherState.failed;
    }
    _notify();
  }

  /// Saves a place the user typed and loads its weather.
  Future<void> usePlace(Place chosen) async {
    final coarse = chosen.coarse;
    await savePlace(place: coarse, useDeviceLocation: false);
    await refresh(coarse);
  }

  /// Asks for the device's approximate location, then saves and uses it.
  /// Returns what happened so the screen can explain a refusal.
  Future<LocationOutcome> useDeviceLocation() async {
    final result = await location.approximatePlace();
    if (result.outcome != LocationOutcome.got || result.place == null) {
      return result.outcome;
    }
    await savePlace(place: result.place, useDeviceLocation: true);
    await refresh(result.place);
    return LocationOutcome.got;
  }

  /// Forgets the place the user chose, and stops showing the weather.
  Future<void> forgetPlace() async {
    await savePlace(useDeviceLocation: false);
    reset();
  }

  /// Drops what is held in memory WITHOUT writing anything. Used after
  /// "Delete my data", which has already erased the settings: writing here
  /// would put a row straight back into an emptied store.
  void reset() {
    place = null;
    weather = null;
    state = WeatherState.noPlace;
    error = null;
    _notify();
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
