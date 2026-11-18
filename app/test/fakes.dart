import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:bird_audio/bird_audio.dart';
import 'package:ecoyard/app/app_environment.dart';
import 'package:ecoyard/app/content.dart';
import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:ecoyard/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart'
    show ImageProvider, MemoryImage, Size, Text;

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
            sentAudioOffDevice: true,
            detections: const [Detection(speciesText: 'Northern Cardinal')],
          );

  @override
  final String id;
  @override
  String get label => id == 'naturelm' ? 'NatureLM' : 'BirdNET';

  @override
  bool get sendsAudioOffDevice => true;
  @override
  bool get noDetectionIsFinal => true;

  bool available;
  Object outcome;
  int identifyCalls = 0;

  /// When set, identify waits for it before answering (a slow service).
  Completer<void>? gate;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<IdentificationResult> identify(AudioClip clip) async {
    identifyCalls++;
    if (gate != null) await gate!.future;
    final o = outcome;
    if (o is IdentificationResult) return o;
    throw o;
  }
}

/// The real repo content, read synchronously so it completes under fake async.
AppContent realAppContent({bool withPhotos = true}) {
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
    photos: withPhotos
        ? PhotoCredits.fromJson(read('photo_credits.json'))
        : PhotoCredits.empty(),
  );
}

/// 10 November 2026: autumn, so leaf cover and planting are in season.
DateTime fixedNow() => DateTime.utc(2026, 11, 10, 12);

/// A weather service that answers from memory. Tests never hit the network.
class FakeWeather implements WeatherService, PlaceSearch {
  FakeWeather({
    this.weather,
    this.failWith,
    this.matches = const [],
    DateTime Function()? now,
  }) : _now = now ?? fixedNow;

  /// Stamps readings, so staleness can be tested against the same clock the
  /// app uses.
  final DateTime Function() _now;

  /// What to return. Null means a plain failure.
  WeatherNow? weather;

  /// Set to make the next call fail with this message.
  String? failWith;

  /// What a place search returns.
  List<Place> matches;

  final asked = <Place>[];
  final searched = <String>[];

  @override
  Future<WeatherNow> forPlace(Place place) async {
    asked.add(place);
    final f = failWith;
    if (f != null) throw WeatherUnavailable(f);
    return weather ??
        WeatherNow(
          tempF: 58,
          highF: 61,
          lowF: 44,
          condition: WeatherCondition.cloudy,
          observedAt: _now().toUtc().toIso8601String(),
        );
  }

  @override
  Future<List<Place>> search(String query) async {
    searched.add(query);
    final f = failWith;
    if (f != null) throw WeatherUnavailable(f);
    return matches;
  }
}

/// A device location that answers however the test wants.
class FakeLocation implements DeviceLocation {
  FakeLocation({this.outcome = LocationOutcome.got, this.place});

  LocationOutcome outcome;
  Place? place;
  var calls = 0;

  /// A misbehaving source: reports a refusal but still returns a position.
  /// Nothing may be saved from it.
  bool alsoGivePlaceOnRefusal = false;

  @override
  Future<LocationResult> approximatePlace() async {
    calls++;
    if (outcome != LocationOutcome.got) {
      return LocationResult(
        outcome,
        alsoGivePlaceOnRefusal ? place?.coarse : null,
      );
    }
    return LocationResult(
      outcome,
      (place ?? const Place(name: 'Nearby', latitude: 40.74, longitude: -74.55))
          .coarse,
    );
  }
}

/// Records what the user was offered to share. Never opens a share sheet.
class FakeExporter implements DataExporter {
  FakeExporter({this.outcome = ExportOutcome.shared});

  ExportOutcome outcome;
  final shared = <String>[];
  var sweeps = 0;
  Rect? lastOrigin;

  @override
  Future<ExportOutcome> export(String json, {Rect? origin}) async {
    shared.add(json);
    lastOrigin = origin;
    return outcome;
  }

  @override
  Future<int> sweep() async {
    sweeps++;
    return 0;
  }
}

/// Records what was scheduled. Never touches the system.
class FakeReminders implements ReminderScheduler {
  FakeReminders({
    this.allowed = false,
    this.askAnswer = ReminderPermission.granted,
  });

  /// What the system currently allows.
  bool allowed;

  /// What the user answers if asked.
  ReminderPermission askAnswer;
  var asked = 0;
  var cancels = 0;
  Object? failSchedule;
  List<DateTime> scheduled = [];
  var scheduleCalls = 0;

  @override
  Future<bool> isAllowed() async => allowed;

  @override
  Future<ReminderPermission> requestPermission() async {
    asked++;
    allowed = askAnswer == ReminderPermission.granted;
    return askAnswer;
  }

  @override
  Future<void> schedule(List<DateTime> times) async {
    scheduleCalls++;
    if (failSchedule != null) throw failSchedule!;
    scheduled = List.of(times);
  }

  @override
  Future<void> cancelAll() async {
    cancels++;
    scheduled = [];
  }
}

/// An offline model that never touches disk, network or TFLite.
class FakeOffline implements OfflineModel {
  FakeOffline({
    this.ready = false,
    OfflineModelConfig? config,
    this.provider = const _NoLocal(),
  }) : config = config ?? downloadableConfig;

  /// A configuration with both addresses filled in.
  static const downloadableConfig = OfflineModelConfig(
    modelVersion: 'v1',
    sampleRate: 48000,
    minTailSeconds: 1,
    topN: 5,
    scoreFloor: 0.25,
    files: [
      OfflineFile(
        role: 'model',
        name: 'v1.tflite',
        url: 'https://h.test/m',
        bytes: 51726412,
        sha256: 'a',
      ),
      OfflineFile(
        role: 'labels',
        name: 'v1-labels.txt',
        url: 'https://h.test/l',
        bytes: 259740,
        sha256: 'b',
      ),
    ],
  );

  @override
  final OfflineModelConfig config;
  @override
  final IdentificationProvider provider;

  bool ready;
  var downloads = 0;
  var removes = 0;
  var closes = 0;
  var sweeps = 0;

  /// Set to make the next download fail, or hold it open until completed.
  Object? failDownload;
  Completer<void>? hold;
  bool removeOk = true;
  CancelToken? lastCancel;
  void Function(int, int?)? lastProgress;

  @override
  Future<bool> isReady() async => ready;

  @override
  Future<void> download({
    ProgressCallback? onProgress,
    CancelToken? cancel,
  }) async {
    downloads++;
    lastCancel = cancel;
    lastProgress = onProgress;
    final total = config.totalBytes;
    onProgress?.call(0, total);
    if (hold != null) {
      await hold!.future;
      if (cancel?.isCancelled ?? false) throw const ModelDownloadCancelled();
    }
    if (failDownload != null) throw failDownload!;
    onProgress?.call(total, total);
    ready = true;
  }

  @override
  Future<bool> remove() async {
    removes++;
    if (removeOk) ready = false;
    return removeOk;
  }

  @override
  Future<void> close() async => closes++;

  @override
  Future<void> sweepPartials() async => sweeps++;
}

class _NoLocal implements IdentificationProvider {
  const _NoLocal();
  @override
  String get id => 'birdnet-local';
  @override
  String get label => 'BirdNET on this phone';
  @override
  bool get sendsAudioOffDevice => false;
  @override
  bool get noDetectionIsFinal => false;
  @override
  Future<bool> isAvailable() async => false;
  @override
  Future<IdentificationResult> identify(AudioClip clip) =>
      throw const ProviderException(FailureKind.unavailable, 'none');
}

/// A 1x1 transparent PNG, so tests can show an image without the network.
final Uint8List _pixel = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0B,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x60,
  0x00,
  0x02,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x7A,
  0x5E,
  0xAB,
  0x3F,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

/// Answers photo lookups from a map (name -> photo), and records the asks.
class FakePhotoLookup implements SpeciesPhotoLookup {
  FakePhotoLookup([this.photos = const {}]);
  final Map<String, RemotePhoto> photos;
  final asked = <String>[];
  Completer<RemotePhoto?>? hold;

  @override
  Future<RemotePhoto?> find({
    required String name,
    String? scientificName,
  }) async {
    asked.add(name);
    if (hold != null) return hold!.future;
    return photos[name];
  }
}

AppEnvironment fakeEnv({
  List<IdentificationProvider>? providers,
  FakeRecorder? recorder,
  PlanStore? store,
  Future<AppContent> Function()? loadContent,
  Future<PlanStore> Function()? openPlanStore,
  AppStorage? storage,
  Future<AppStorage> Function()? openStorage,
  AudioCache? audioCache,
  WeatherService? weather,
  DeviceLocation? location,
  DataExporter? exporter,
  ReminderScheduler? reminders,
  OfflineModel? offline,
  SpeciesPhotoLookup? photoLookup,
  ImageProvider Function(String url)? photoImage,
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
  weather: weather ?? FakeWeather(),
  location: location ?? FakeLocation(),
  exporter: exporter ?? FakeExporter(),
  reminders: reminders ?? FakeReminders(),
  offline: offline ?? FakeOffline(),
  photoLookup: photoLookup ?? FakePhotoLookup(),
  photoImage: photoImage ?? (_) => MemoryImage(_pixel),
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
        sentAudioOffDevice: true,
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
