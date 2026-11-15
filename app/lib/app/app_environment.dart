import 'package:bird_audio/bird_audio.dart';

import 'content.dart';

/// Everything the screens need from the outside world, passed in through
/// constructors. No singletons: tests build a fake, the app builds a live one.
class AppEnvironment {
  const AppEnvironment({
    required this.chain,
    required this.newRecorder,
    required this.loadContent,
    required this.openStorage,
    required this.audioCache,
    required this.weather,
    required this.location,
    this.now = DateTime.now,
  });

  /// Real services: NatureLM via the router, then BirdNET online; the bundled
  /// content; the plan in a SQLite file on the device.
  factory AppEnvironment.live() => AppEnvironment(
    chain: standardOnlineChain(),
    newRecorder: RecordPackageRecorder.new,
    loadContent: loadBundledContent,
    openStorage: SqliteAppStorage.open,
    audioCache: AudioCache(),
    weather: OpenMeteoWeather(),
    location: const GeolocatorLocation(),
  );

  final ProviderChain chain;

  /// Creates a recorder for a screen to own and dispose.
  final ClipRecorder Function() newRecorder;

  /// Loads the reference content. May throw; the app shows a retry screen.
  final Future<AppContent> Function() loadContent;

  /// Opens the app database (plan + settings). May throw; the My Plan and
  /// Settings tabs then say so.
  final Future<AppStorage> Function() openStorage;

  /// Removes recordings left behind by a crash. Never throws.
  final AudioCache audioCache;

  /// The weather service. Also used to search for a town.
  final WeatherService weather;

  /// The device's approximate location, asked for only when the user taps
  /// "Use my area".
  final DeviceLocation location;

  /// The clock. Used for the month (advice) and for plan timestamps.
  final DateTime Function() now;
}
