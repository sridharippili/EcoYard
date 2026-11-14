import 'package:bird_audio/bird_audio.dart';

import 'sample_content.dart';

/// Everything the screens need from the outside world, passed in through
/// constructors. No singletons: tests build a fake, the app builds a live one.
class AppEnvironment {
  const AppEnvironment({
    required this.chain,
    required this.newRecorder,
    this.loadHomeSample = loadBundledHomeSample,
  });

  /// Real services: NatureLM via the router, then BirdNET online.
  factory AppEnvironment.live() => AppEnvironment(
    chain: standardOnlineChain(),
    newRecorder: RecordPackageRecorder.new,
  );

  final ProviderChain chain;

  /// Creates a recorder for a screen to own and dispose.
  final ClipRecorder Function() newRecorder;

  /// Placeholder Home content (weather, tip) until Phase 2 content exists.
  final Future<Map<String, dynamic>> Function() loadHomeSample;
}
