import 'dart:typed_data';

import 'package:bird_audio/bird_audio.dart';
import 'package:ecoyard/app/app_environment.dart';
import 'package:ecoyard/main.dart';
import 'package:flutter_test/flutter_test.dart';

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

AppEnvironment fakeEnv({
  List<IdentificationProvider>? providers,
  FakeRecorder? recorder,
}) => AppEnvironment(
  chain: ProviderChain(providers ?? [FakeProvider('naturelm')]),
  newRecorder: () => recorder ?? FakeRecorder(),
  loadHomeSample: () async => _homeSample,
);

const _homeSample = <String, dynamic>{
  'greeting': 'Hi there!',
  'subtitle': 'Test subtitle',
  'weather': {'place': 'Test place', 'summary': 'Test summary', 'tempF': 50},
  'tip': {'title': "Today's Habitat Tip", 'body': 'Test tip body.'},
};

/// Pumps the whole app with [env] and lets it settle.
Future<void> pumpApp(WidgetTester tester, AppEnvironment env) async {
  await tester.pumpWidget(EcoYardApp(env: env));
  await tester.pumpAndSettle();
}
