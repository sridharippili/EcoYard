import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bird_audio/bird_audio.dart';
import 'package:crypto/crypto.dart';
import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Serves a different body per URL, and counts requests.
class RouterClient extends http.BaseClient {
  RouterClient(this.bodies, {this.slow = false});
  final Map<String, List<int>> bodies;
  final bool slow;
  final requested = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requested.add(request.url.toString());
    final body = bodies[request.url.toString()];
    if (body == null) {
      return http.StreamedResponse(const Stream.empty(), 404, request: request);
    }
    Stream<List<int>> chunks() async* {
      for (var i = 0; i < body.length; i += 100) {
        yield body.sublist(i, (i + 100).clamp(0, body.length));
        if (slow) await Future<void>.delayed(const Duration(milliseconds: 2));
      }
    }

    return http.StreamedResponse(chunks(), 200,
        contentLength: body.length, request: request);
  }
}

class FakeRunner implements BirdModelRunner {
  var closed = 0;
  @override
  int get windowSamples => 100;
  @override
  int get classCount => 3;
  @override
  Future<Float32List> logitsFor(Float32List window) async =>
      Float32List.fromList([0, 0, 0]);
  @override
  Future<void> close() async => closed++;
}

void main() {
  late Directory dir;
  final model = Uint8List.fromList(List.generate(1000, (i) => i % 251));
  final labelsText = Uint8List.fromList(
    'Cardinalis cardinalis_Northern Cardinal\n'.codeUnits,
  );

  OfflineModelConfig config({String modelUrl = 'https://h.test/m'}) =>
      OfflineModelConfig(
        modelVersion: 'v1',
        sampleRate: 48000,
        minTailSeconds: 1,
        topN: 5,
        scoreFloor: 0.25,
        files: [
          OfflineFile(
            role: 'model',
            name: 'v1.tflite',
            url: modelUrl,
            bytes: model.length,
            sha256: sha256.convert(model).toString(),
          ),
          OfflineFile(
            role: 'labels',
            name: 'v1-labels.txt',
            url: 'https://h.test/l',
            bytes: labelsText.length,
            sha256: sha256.convert(labelsText).toString(),
          ),
        ],
      );

  late RouterClient client;
  late List<FakeRunner> runners;
  Object? loadFails;

  OfflineModelHost host({String modelUrl = 'https://h.test/m'}) =>
      OfflineModelHost(
        config: config(modelUrl: modelUrl),
        store: ModelStore(dir: dir, client: client),
        loadRunner: (path) async {
          if (loadFails != null) throw loadFails!;
          expect(File(path).existsSync(), isTrue);
          final r = FakeRunner();
          runners.add(r);
          return r;
        },
      );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('ecoyard_host_');
    client = RouterClient(
        {'https://h.test/m': model, 'https://h.test/l': labelsText});
    runners = [];
    loadFails = null;
  });
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  List<String> filesLeft() =>
      dir.listSync().map((e) => e.uri.pathSegments.last).toList()..sort();

  test('is not ready before a download, and never touches the network',
      () async {
    final h = host();
    expect(await h.isReady(), isFalse);
    expect(await h.provider.isAvailable(), isFalse);
    expect(client.requested, isEmpty);
  });

  test(
      'downloads both files, reports steady progress to the total, and '
      'test-opens the model', () async {
    final h = host();
    final seen = <int>[];
    int? total;
    await h.download(onProgress: (r, t) {
      seen.add(r);
      total = t;
    });
    expect(await h.isReady(), isTrue);
    expect(await h.provider.isAvailable(), isTrue);
    expect(total, model.length + labelsText.length);
    expect(seen.last, total);
    for (var i = 1; i < seen.length; i++) {
      expect(seen[i], greaterThanOrEqualTo(seen[i - 1]));
    }
    expect(runners, hasLength(1));
    expect(runners.single.closed, 1, reason: 'the test-open must be closed');
    expect(filesLeft(), ['v1-labels.txt', 'v1.tflite']);
  });

  test('a configuration with no address makes no request and says so',
      () async {
    final h = host(modelUrl: '');
    await expectLater(h.download(), throwsA(isA<ModelDownloadException>()));
    expect(client.requested, isEmpty);
    expect(await h.isReady(), isFalse);
  });

  test('if the second file fails, the first is removed too', () async {
    client.bodies.remove('https://h.test/l');
    final h = host();
    await expectLater(h.download(), throwsA(isA<ModelDownloadException>()));
    expect(await h.isReady(), isFalse);
    expect(filesLeft(), isEmpty);
  });

  test('a model that will not open is removed, with an honest message',
      () async {
    loadFails = StateError('bad model');
    final h = host();
    await expectLater(
      h.download(),
      throwsA(isA<ModelDownloadException>().having(
          (e) => e.message, 'message', contains('could not be opened'))),
    );
    expect(await h.isReady(), isFalse);
    expect(filesLeft(), isEmpty);
  });

  test('cancelling leaves nothing behind', () async {
    client = RouterClient(client.bodies, slow: true);
    final h = host();
    final cancel = CancelToken();
    final run = h.download(
      cancel: cancel,
      onProgress: (r, _) {
        if (r > 300) cancel.cancel();
      },
    );
    await expectLater(run, throwsA(isA<ModelDownloadCancelled>()));
    expect(await h.isReady(), isFalse);
    expect(filesLeft(), isEmpty);
  });

  test('remove closes the model and deletes every file', () async {
    final h = host();
    await h.download();
    File('${dir.path}/v1.tflite.part').writeAsStringSync('x');
    expect(await h.remove(), isTrue);
    expect(await h.isReady(), isFalse);
    expect(filesLeft(), isEmpty);
  });

  test('a purged file means not ready again', () async {
    final h = host();
    await h.download();
    File('${dir.path}/v1-labels.txt').deleteSync();
    expect(await h.isReady(), isFalse);
  });

  test('a file of the wrong size is not ready', () async {
    final h = host();
    await h.download();
    File('${dir.path}/v1.tflite').writeAsBytesSync([1, 2, 3]);
    expect(await h.isReady(), isFalse);
  });

  test('sweepPartials removes only partial downloads', () async {
    final h = host();
    await h.download();
    File('${dir.path}/v1.tflite.part').writeAsStringSync('x');
    await h.sweepPartials();
    expect(filesLeft(), ['v1-labels.txt', 'v1.tflite']);
  });

  test('an empty configuration is never ready and cannot download', () async {
    final h = OfflineModelHost(
      config: OfflineModelConfig.none,
      store: ModelStore(dir: dir, client: client),
    );
    expect(await h.isReady(), isFalse);
    await expectLater(h.download(), throwsA(isA<ModelDownloadException>()));
  });

  group('the chain', () {
    test('forgetHealth lets a provider that was down be tried again', () async {
      var up = false;
      final chain = ProviderChain([_Switch(() => up), _Always()]);
      expect((await chain.checkHealth()).available['switch'], isFalse);
      up = true;
      expect((await chain.checkHealth()).available['switch'], isFalse,
          reason: 'cached');
      chain.forgetHealth();
      expect((await chain.checkHealth()).available['switch'], isTrue);
    });
  });

  group('AudioCache', () {
    test('sweeps leftover .wav recordings too, and only our names', () async {
      final keep = [
        File('${dir.path}/ecoyard_5.wav.bak'),
        File('${dir.path}/other_5.wav'),
        File('${dir.path}/ecoyard_x.wav'),
      ];
      final ours = [
        File('${dir.path}/ecoyard_5.wav'),
        File('${dir.path}/ecoyard_6.m4a'),
      ];
      for (final f in [...keep, ...ours]) {
        f.writeAsStringSync('x');
      }
      expect(await AudioCache(tempDir: () async => dir).sweep(), 2);
      for (final f in ours) {
        expect(f.existsSync(), isFalse);
      }
      for (final f in keep) {
        expect(f.existsSync(), isTrue);
      }
    });
  });
}

class _Switch implements IdentificationProvider {
  _Switch(this.up);
  final bool Function() up;
  @override
  String get id => 'switch';
  @override
  String get label => 'Switch';
  @override
  bool get sendsAudioOffDevice => false;
  @override
  bool get noDetectionIsFinal => true;
  @override
  Future<bool> isAvailable() async => up();
  @override
  Future<IdentificationResult> identify(AudioClip clip) =>
      throw UnimplementedError();
}

class _Always extends _Switch {
  _Always() : super(() => true);
  @override
  String get id => 'always';
}
