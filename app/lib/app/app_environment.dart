import 'package:bird_audio/bird_audio.dart';

import 'content.dart';
import 'sample_content.dart';

/// Everything the screens need from the outside world, passed in through
/// constructors. No singletons: tests build a fake, the app builds a live one.
class AppEnvironment {
  const AppEnvironment({
    required this.chain,
    required this.newRecorder,
    required this.loadContent,
    required this.openPlanStore,
    this.now = DateTime.now,
    this.loadHomeSample = loadBundledHomeSample,
  });

  /// Real services: NatureLM via the router, then BirdNET online; the bundled
  /// content; the plan in a SQLite file on the device.
  factory AppEnvironment.live() => AppEnvironment(
    chain: standardOnlineChain(),
    newRecorder: RecordPackageRecorder.new,
    loadContent: loadBundledContent,
    openPlanStore: SqflitePlanStore.open,
  );

  final ProviderChain chain;

  /// Creates a recorder for a screen to own and dispose.
  final ClipRecorder Function() newRecorder;

  /// Loads the reference content. May throw; the app shows a retry screen.
  final Future<AppContent> Function() loadContent;

  /// Opens the plan database. May throw; the My Plan tab then says so.
  final Future<PlanStore> Function() openPlanStore;

  /// The clock. Used for the month (advice) and for plan timestamps.
  final DateTime Function() now;

  /// Placeholder Home content (weather, tip) until the Home phase.
  final Future<Map<String, dynamic>> Function() loadHomeSample;
}
