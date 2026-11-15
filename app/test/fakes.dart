import 'dart:io';
import 'dart:typed_data';

import 'package:bird_audio/bird_audio.dart';
import 'package:ecoyard/app/app_environment.dart';
import 'package:ecoyard/app/content.dart';
import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:ecoyard/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Size, Text;

class FakeRecorder implements ClipRecorder {
  FakeRecorder({this.permission = true, this.stopThrows = false});

  bool permission;
  bool stopThrows;
  int startCalls = 0;
  int stopCalls = 0;
  int cancelCalls = 0;
  bool disposed = false;

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<void> start() async => startCalls++;

  @override
  Future<AudioClip> stop() async {
    stopCalls++;
    if (stopThrows) throw StateError('no file');
    return AudioClip(bytes: Uint8List.fromList([1, 2, 3]));
  }

  @override
  Future<void> cancel() async => cancelCalls++;

  @override
  Future<void> dispose() async => disposed = true;
}

class FakeProvider implements IdentificationProvider {
  FakeProvider(this.id, {this.available = true, Object? outcome})
    : outcome =
          outcome ??
          IdentificationResult(
            providerId: id,
            providerLabel: id == 'naturelm' ? 'NatureLM' : 'BirdNET',
            detections: const [Detection(speciesText: 'Northern Cardinal')],
          );

  @override
  final String id;
  @override
  String get label => id == 'naturelm' ? 'NatureLM' : 'BirdNET';

  bool available;
  Object outcome;
  int identifyCalls = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<IdentificationResult> identify(AudioClip clip) async {
    identifyCalls++;
    final o = outcome;
    if (o is IdentificationResult) return o;
    throw o;
  }
}

/// The real repo content, read synchronously so it completes under fake async.
AppContent realAppContent() {
  String read(String n) => File('../content/$n').readAsStringSync();
  return AppContent(
    ReferenceRepository.fromJson(
      ContentFiles(
        birds: read('birds.json'),
        plants: read('plants.json'),
        birdPlant: read('bird_plant.json'),
        actions: read('actions.json'),
        tips: read('tips.json'),
        aliases: read('taxonomy_aliases.json'),
      ),
    ),
  );
}

/// 10 November 2026: autumn, so leaf cover and planting are in season.
DateTime fixedNow() => DateTime.utc(2026, 11, 10, 12);

AppEnvironment fakeEnv({
  List<IdentificationProvider>? providers,
  FakeRecorder? recorder,
  PlanStore? store,
  Future<AppContent> Function()? loadContent,
  Future<PlanStore> Function()? openPlanStore,
  AppStorage? storage,
  Future<AppStorage> Function()? openStorage,
  AudioCache? audioCache,
  bool onboarded = true,
  DateTime Function()? now,
}) => AppEnvironment(
  chain: ProviderChain(providers ?? [FakeProvider('naturelm')]),
  newRecorder: () => recorder ?? FakeRecorder(),
  loadContent: loadContent ?? () async => realAppContent(),
  openStorage:
      openStorage ??
      () async =>
          storage ??
          InMemoryAppStorage(
            plans: openPlanStore != null
                ? await openPlanStore()
                : (store ?? InMemoryPlanStore()),
            settings: InMemorySettingsStore({
              if (onboarded) AppSettings.keyOnboarded: 'true',
            }),
          ),
  audioCache: audioCache ?? FakeAudioCache(),
  now: now ?? fixedNow,
);

/// Counts sweeps and does no file I/O (real I/O never completes under the
/// widget tests' fake clock).
class FakeAudioCache implements AudioCache {
  int sweeps = 0;
  @override
  Future<int> sweep() async {
    sweeps++;
    return 0;
  }
}

/// Pumps the whole app with [env] and lets it settle.
Future<void> pumpApp(WidgetTester tester, AppEnvironment env) async {
  // A tall phone-width screen, so long result lists need no scrolling.
  tester.view.physicalSize = const Size(420, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(EcoYardApp(env: env));
  await tester.pumpAndSettle();
}

/// A provider that answers with [name] (and optional [confidence]).
FakeProvider answering(String name, {double? confidence, String? scientific}) =>
    FakeProvider(
      'naturelm',
      outcome: IdentificationResult(
        providerId: 'naturelm',
        providerLabel: 'NatureLM',
        detections: [
          Detection(
            speciesText: name,
            scientificName: scientific,
            confidence: confidence,
          ),
        ],
      ),
    );

/// Opens the Birds tab, records and stops, so the result is on screen.
Future<void> recordAndStop(WidgetTester tester) async {
  await tester.tap(find.text('Birds').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Tap to record'));
  await tester.pump();
  await tester.tap(find.textContaining('Tap to stop'));
  await tester.pumpAndSettle();
}

/// Every piece of text currently built, for copy checks.
List<String> allText(WidgetTester tester) => [
  for (final t in tester.widgetList<Text>(find.byType(Text)))
    t.data ?? t.textSpan?.toPlainText() ?? '',
];

/// Overflowing layouts on screen, as widget chains, ignoring Home (its header
/// and weather card overflow at 320 px and 2x text: known, Phase 0 starter,
/// listed in docs/STATE.md). Clears the pending framework exception.
List<String> overflowsOutsideHome(WidgetTester tester) {
  final found = <String>[];
  for (final r in tester.allRenderObjects) {
    if (!r.toStringShort().contains('OVERFLOWING')) continue;
    final chain =
        ((r.debugCreator as dynamic).element as dynamic).debugGetCreatorChain(
          12,
        ) as String;
    if (chain.contains('_Header') || chain.contains('_WeatherCard')) continue;
    found.add(chain);
  }
  while (tester.takeException() != null) {}
  return found;
}
