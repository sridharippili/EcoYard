import 'dart:typed_data';

import 'package:bird_audio/bird_audio.dart';
import 'package:flutter_test/flutter_test.dart';

/// A tiny valid WAV so the pipeline has something real to decode.
Uint8List wavOf(int samples, {int rate = 100}) {
  final data = BytesBuilder();
  for (var i = 0; i < samples; i++) {
    final b = ByteData(2)..setInt16(0, (i % 50) * 100, Endian.little);
    data.add(b.buffer.asUint8List());
  }
  final fmt = ByteData(16)
    ..setUint16(0, 1, Endian.little)
    ..setUint16(2, 1, Endian.little)
    ..setUint32(4, rate, Endian.little)
    ..setUint32(8, rate * 2, Endian.little)
    ..setUint16(12, 2, Endian.little)
    ..setUint16(14, 16, Endian.little);
  final body = BytesBuilder()
    ..add('fmt '.codeUnits)
    ..add((ByteData(4)..setUint32(0, 16, Endian.little)).buffer.asUint8List())
    ..add(fmt.buffer.asUint8List())
    ..add('data'.codeUnits)
    ..add((ByteData(4)..setUint32(0, samples * 2, Endian.little))
        .buffer
        .asUint8List())
    ..add(data.toBytes());
  final b = body.toBytes();
  return (BytesBuilder()
        ..add('RIFF'.codeUnits)
        ..add((ByteData(4)..setUint32(0, b.length + 4, Endian.little))
            .buffer
            .asUint8List())
        ..add('WAVE'.codeUnits)
        ..add(b))
      .toBytes();
}

class FakeRunner implements BirdModelRunner {
  FakeRunner({this.logits, this.throwOnRun});
  @override
  final int windowSamples = 100;
  @override
  final int classCount = 3;
  final List<double>? logits;
  final Object? throwOnRun;
  var calls = 0;
  var closed = 0;

  @override
  Future<Float32List> logitsFor(Float32List window) async {
    calls++;
    if (throwOnRun != null) throw throwOnRun!;
    return Float32List.fromList(logits ?? [-9, -9, -9]);
  }

  @override
  Future<void> close() async => closed++;
}

const labels = [
  BirdNetLabel('Cardinalis cardinalis', 'Northern Cardinal'),
  BirdNetLabel('Cyanocitta cristata', 'Blue Jay'),
  BirdNetLabel('Human vocal', 'Human vocal'),
];

const settings = BirdNetSettings(
  sampleRate: 100,
  minTailSeconds: 0.3,
  topN: 2,
  scoreFloor: 0.5,
);

void main() {
  late FakeRunner runner;
  var loads = 0;
  var labelLoads = 0;

  BirdNetLocalProvider make({
    bool ready = true,
    FakeRunner? r,
    Object? loadError,
    Object? labelError,
    bool Function(BirdNetLabel)? allowed,
  }) {
    runner = r ?? FakeRunner(logits: [4, -9, -9]);
    loads = 0;
    labelLoads = 0;
    return BirdNetLocalProvider(
      isModelReady: () async => ready,
      loadRunner: () async {
        loads++;
        if (loadError != null) throw loadError;
        return runner;
      },
      loadLabels: () async {
        labelLoads++;
        if (labelError != null) throw labelError;
        return labels;
      },
      settings: settings,
      allowed: allowed,
    );
  }

  final clip = AudioClip(bytes: wavOf(100), fileName: 'r.wav');

  test('it never sends audio, and its silence is not the final word', () {
    final p = make();
    expect(p.sendsAudioOffDevice, isFalse);
    expect(p.noDetectionIsFinal, isFalse);
    expect(p.id, 'birdnet-local');
  });

  group('availability', () {
    test('follows the files on disk and never loads the model', () async {
      final ready = make();
      expect(await ready.isAvailable(), isTrue);
      expect(loads, 0, reason: 'probing must not load 52 MB');
      final missing = make(ready: false);
      expect(await missing.isAvailable(), isFalse);
    });

    test('a broken check is "not available", not a crash', () async {
      final p = BirdNetLocalProvider(
        isModelReady: () async => throw StateError('disk gone'),
        loadRunner: () async => FakeRunner(),
        loadLabels: () async => labels,
        settings: settings,
      );
      expect(await p.isAvailable(), isFalse);
    });
  });

  group('identifying', () {
    test('answers with the ranked species and says nothing was sent', () async {
      final p = make(r: FakeRunner(logits: [4, 2, -9]));
      final res = await p.identify(clip);
      expect(res.sentAudioOffDevice, isFalse);
      expect(res.providerId, 'birdnet-local');
      expect(res.top.speciesText, 'Northern Cardinal');
      expect(res.top.scientificName, 'Cardinalis cardinalis');
      expect(res.top.confidence, greaterThan(0.9));
      expect(res.detections, hasLength(2));
    });

    test('the model and labels load once, however many recordings', () async {
      final p = make();
      await p.identify(clip);
      await p.identify(clip);
      expect(loads, 1);
      expect(labelLoads, 1);
    });

    test('two recordings at once still load it once', () async {
      final p = make();
      await Future.wait([p.identify(clip), p.identify(clip)]);
      expect(loads, 1);
    });

    test('nothing above the floor is "heard nothing" (not final)', () async {
      final p = make(r: FakeRunner(logits: [-9, -9, -9]));
      await expectLater(
        p.identify(clip),
        throwsA(isA<ProviderException>()
            .having((e) => e.kind, 'kind', FailureKind.noDetection)),
      );
      expect(p.noDetectionIsFinal, isFalse);
    });

    test('the allowed filter keeps a species out of the answer', () async {
      final p = make(
        r: FakeRunner(logits: [4, 2, -9]),
        allowed: (l) => l.commonName != 'Northern Cardinal',
      );
      final res = await p.identify(clip);
      expect(res.top.speciesText, 'Blue Jay');
    });
  });

  group('failures fall through instead of poisoning the chain', () {
    test('model not downloaded -> unavailable, without loading', () async {
      final p = make(ready: false);
      await expectLater(
        p.identify(clip),
        throwsA(isA<ProviderException>()
            .having((e) => e.kind, 'kind', FailureKind.unavailable)),
      );
      expect(loads, 0);
    });

    test('a model that will not load -> unavailable', () async {
      final p = make(loadError: StateError('corrupt'));
      await expectLater(
        p.identify(clip),
        throwsA(isA<ProviderException>()
            .having((e) => e.kind, 'kind', FailureKind.unavailable)),
      );
    });

    test('labels that will not load -> unavailable', () async {
      final p = make(labelError: StateError('no labels'));
      await expectLater(
        p.identify(clip),
        throwsA(isA<ProviderException>()
            .having((e) => e.kind, 'kind', FailureKind.unavailable)),
      );
    });

    test(
        'a runner that dies -> unavailable AND the model is closed, so a '
        'corrupt model is not retried for every recording', () async {
      final r = FakeRunner(throwOnRun: StateError('interpreter died'));
      final p = make(r: r);
      await expectLater(
        p.identify(clip),
        throwsA(isA<ProviderException>()
            .having((e) => e.kind, 'kind', FailureKind.unavailable)),
      );
      expect(r.closed, greaterThan(0));
    });

    test('a recording it cannot read -> badResponse, model stays loaded',
        () async {
      final p = make();
      await p.identify(clip); // load it first
      await expectLater(
        p.identify(AudioClip(bytes: Uint8List(50), fileName: 'bad.wav')),
        throwsA(isA<ProviderException>()
            .having((e) => e.kind, 'kind', FailureKind.badResponse)),
      );
      expect(runner.closed, 0);
    });

    test('audio too short to score is "heard nothing", not an error', () async {
      final p = make();
      await expectLater(
        p.identify(AudioClip(bytes: wavOf(5), fileName: 'tiny.wav')),
        throwsA(isA<ProviderException>()
            .having((e) => e.kind, 'kind', FailureKind.noDetection)),
      );
    });
  });

  group('close', () {
    test('frees the model and the next recording loads it again', () async {
      final p = make();
      await p.identify(clip);
      await p.close();
      expect(runner.closed, 1);
      await p.identify(clip);
      expect(loads, 2);
    });

    test('closing twice, or before any use, is harmless', () async {
      final p = make();
      await p.close();
      await p.close();
      expect(runner.closed, 0);
    });
  });
}
