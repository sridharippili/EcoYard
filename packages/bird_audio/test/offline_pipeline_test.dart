import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bird_audio/bird_audio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a WAV file in memory.
Uint8List wav({
  required List<double> samples, // interleaved if channels > 1
  int rate = 48000,
  int channels = 1,
  bool float32 = false,
  bool extensible = false,
  List<List<int>> extraChunksBeforeData = const [],
  int? dataSizeOverride,
  bool oddPadChunk = false,
}) {
  final bytesPer = float32 ? 4 : 2;
  final data = BytesBuilder();
  for (final s in samples) {
    final b = ByteData(bytesPer);
    if (float32) {
      b.setFloat32(0, s, Endian.little);
    } else {
      b.setInt16(0, (s * 32767).round(), Endian.little);
    }
    data.add(b.buffer.asUint8List());
  }
  final fmtSize = extensible ? 40 : 16;
  final fmt = ByteData(fmtSize);
  fmt.setUint16(0, extensible ? 0xFFFE : (float32 ? 3 : 1), Endian.little);
  fmt.setUint16(2, channels, Endian.little);
  fmt.setUint32(4, rate, Endian.little);
  fmt.setUint32(8, rate * channels * bytesPer, Endian.little);
  fmt.setUint16(12, channels * bytesPer, Endian.little);
  fmt.setUint16(14, bytesPer * 8, Endian.little);
  if (extensible) {
    fmt.setUint16(16, 22, Endian.little);
    fmt.setUint16(24, float32 ? 3 : 1, Endian.little); // sub-format
  }
  final out = BytesBuilder();
  void chunk(String id, List<int> body) {
    out.add(id.codeUnits);
    final sz = ByteData(4)..setUint32(0, body.length, Endian.little);
    out.add(sz.buffer.asUint8List());
    out.add(body);
    if (body.length.isOdd) out.addByte(0);
  }

  chunk('fmt ', fmt.buffer.asUint8List());
  for (final c in extraChunksBeforeData) {
    chunk('LIST', c);
  }
  if (oddPadChunk) chunk('junk', [1, 2, 3]);
  final dataBytes = data.toBytes();
  out.add('data'.codeUnits);
  final dsz = ByteData(4)
    ..setUint32(0, dataSizeOverride ?? dataBytes.length, Endian.little);
  out.add(dsz.buffer.asUint8List());
  out.add(dataBytes);
  final body = out.toBytes();
  final header = BytesBuilder()
    ..add('RIFF'.codeUnits)
    ..add((ByteData(4)..setUint32(0, body.length + 4, Endian.little))
        .buffer
        .asUint8List())
    ..add('WAVE'.codeUnits)
    ..add(body);
  return header.toBytes();
}

List<double> ramp(int n) => [for (var i = 0; i < n; i++) (i % 100) / 200.0];

class FakeRunner implements BirdModelRunner {
  FakeRunner({this.windowSamples = 8, this.classCount = 4, this.script});

  @override
  final int windowSamples;
  @override
  final int classCount;

  /// Logits to return for call number n (0-based).
  final Float32List Function(int call, Float32List window)? script;

  final windowsSeen = <Float32List>[];
  var closed = 0;

  @override
  Future<Float32List> logitsFor(Float32List window) async {
    windowsSeen.add(Float32List.fromList(window));
    return script?.call(windowsSeen.length - 1, window) ??
        Float32List(classCount);
  }

  @override
  Future<void> close() async => closed++;
}

void main() {
  group('decodeWav', () {
    test('reads 16-bit mono PCM into -1..1 floats', () {
      final pcm = decodeWav(wav(samples: [0, 0.5, -0.5, 1.0], rate: 48000));
      expect(pcm.sampleRate, 48000);
      expect(pcm.samples, hasLength(4));
      expect(pcm.samples[1], closeTo(0.5, 1e-3));
      expect(pcm.samples[2], closeTo(-0.5, 1e-3));
      expect(pcm.samples[3], closeTo(1.0, 1e-3));
    });

    test('reads 32-bit float WAV', () {
      final pcm = decodeWav(wav(samples: [0.25, -0.75], float32: true));
      expect(pcm.samples[0], closeTo(0.25, 1e-6));
      expect(pcm.samples[1], closeTo(-0.75, 1e-6));
    });

    test('averages stereo to mono', () {
      final pcm = decodeWav(
        wav(samples: [0.5, -0.5, 1.0, 0.0], channels: 2, rate: 44100),
      );
      expect(pcm.sampleRate, 44100);
      expect(pcm.samples, hasLength(2));
      expect(pcm.samples[0], closeTo(0.0, 1e-3));
      expect(pcm.samples[1], closeTo(0.5, 1e-3));
    });

    test('skips other chunks (LIST, odd-sized junk) before the data', () {
      final pcm = decodeWav(
        wav(
          samples: [0.5, 0.5],
          extraChunksBeforeData: [
            [1, 2, 3, 4, 5],
          ],
          oddPadChunk: true,
        ),
      );
      expect(pcm.samples, hasLength(2));
    });

    test('handles WAVE_FORMAT_EXTENSIBLE', () {
      final pcm = decodeWav(wav(samples: [0.5, -0.5], extensible: true));
      expect(pcm.samples[0], closeTo(0.5, 1e-3));
      final f = decodeWav(
        wav(samples: [0.5], extensible: true, float32: true),
      );
      expect(f.samples[0], closeTo(0.5, 1e-6));
    });

    test(
        'a data size larger than the file (killed recorder) reads what is '
        'there', () {
      final pcm = decodeWav(
        wav(samples: ramp(10), dataSizeOverride: 4000000),
      );
      expect(pcm.samples, hasLength(10));
    });

    test('a half sample at the end is dropped, not read past the end', () {
      final bytes = wav(samples: [0.1, 0.2, 0.3]);
      final cut = Uint8List.sublistView(bytes, 0, bytes.length - 1);
      expect(decodeWav(cut).samples, hasLength(2));
    });

    test('duration follows the sample rate', () {
      final pcm = decodeWav(wav(samples: ramp(48000)));
      expect(pcm.duration, const Duration(seconds: 1));
    });

    test('clamps out-of-range float samples', () {
      final pcm = decodeWav(wav(samples: [3.0, -3.0], float32: true));
      expect(pcm.samples[0], 1.0);
      expect(pcm.samples[1], -1.0);
    });

    for (final (name, bytes) in <(String, Uint8List)>[
      ('empty', Uint8List(0)),
      ('too short', Uint8List(8)),
      ('not RIFF', Uint8List.fromList(List.filled(64, 7))),
      (
        'an m4a/ISO file',
        Uint8List.fromList([
          0,
          0,
          0,
          24,
          ...'ftypM4A '.codeUnits,
          ...List.filled(40, 0),
        ])
      ),
    ]) {
      test('rejects $name with a FormatException', () {
        expect(() => decodeWav(bytes), throwsFormatException);
      });
    }

    test('rejects 8-bit and 24-bit audio plainly', () {
      final b = wav(samples: [0.1]);
      // Patch bits per sample (offset 12 + 8 + 14 = 34) to 24.
      final patched = Uint8List.fromList(b);
      ByteData.sublistView(patched).setUint16(34, 24, Endian.little);
      expect(
        () => decodeWav(patched),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('Unsupported'))),
      );
    });

    test('rejects data before fmt, zero rate and zero channels', () {
      final noFmt = BytesBuilder()
        ..add('RIFF'.codeUnits)
        ..add([100, 0, 0, 0])
        ..add('WAVE'.codeUnits)
        ..add('data'.codeUnits)
        ..add([2, 0, 0, 0, 1, 1]);
      expect(() => decodeWav(noFmt.toBytes()), throwsFormatException);

      final zeroRate = Uint8List.fromList(wav(samples: [0.1]));
      ByteData.sublistView(zeroRate).setUint32(24, 0, Endian.little);
      expect(() => decodeWav(zeroRate), throwsFormatException);

      final zeroCh = Uint8List.fromList(wav(samples: [0.1]));
      ByteData.sublistView(zeroCh).setUint16(22, 0, Endian.little);
      expect(() => decodeWav(zeroCh), throwsFormatException);
    });
  });

  group('resampleLinear', () {
    test('same rate returns the input', () {
      final a = Float32List.fromList([1, 2, 3]);
      expect(identical(resampleLinear(a, 48000, 48000), a), isTrue);
    });

    test('44.1 kHz to 48 kHz keeps the duration', () {
      final input = Float32List(44100);
      final out = resampleLinear(input, 44100, 48000);
      expect(out.length, 48000);
    });

    test('a slow ramp stays a ramp', () {
      final input =
          Float32List.fromList([for (var i = 0; i < 100; i++) i / 100]);
      final out = resampleLinear(input, 100, 200);
      for (var i = 1; i < out.length; i++) {
        expect(out[i], greaterThanOrEqualTo(out[i - 1] - 1e-6));
      }
      expect(out.first, 0);
    });

    test('empty input and bad rates', () {
      expect(resampleLinear(Float32List(0), 44100, 48000), isEmpty);
      expect(
          () => resampleLinear(Float32List(3), 0, 48000), throwsArgumentError);
      expect(
          () => resampleLinear(Float32List(3), 44100, 0), throwsArgumentError);
    });

    test('a single sample does not read past the end', () {
      final out = resampleLinear(Float32List.fromList([0.5]), 100, 300);
      expect(out.every((v) => v == 0.5), isTrue);
    });
  });

  group('cutWindows', () {
    Float32List n(int len) =>
        Float32List.fromList([for (var i = 0; i < len; i++) i.toDouble()]);

    test('exact multiple gives full windows and no padding', () {
      final w = cutWindows(n(16), 8, minTailSamples: 2);
      expect(w, hasLength(2));
      expect(w[1].first, 8);
      expect(w[1].last, 15);
    });

    test('a long enough tail becomes one padded window', () {
      final w = cutWindows(n(11), 8, minTailSamples: 3);
      expect(w, hasLength(2));
      expect(w[1].sublist(0, 3), [8, 9, 10]);
      expect(w[1].sublist(3).every((v) => v == 0), isTrue);
    });

    test('a too-short tail is dropped', () {
      expect(cutWindows(n(10), 8, minTailSamples: 3), hasLength(1));
    });

    test('audio shorter than a window is padded if long enough, else empty',
        () {
      expect(cutWindows(n(5), 8, minTailSamples: 3), hasLength(1));
      expect(cutWindows(n(2), 8, minTailSamples: 3), isEmpty);
      expect(cutWindows(Float32List(0), 8, minTailSamples: 1), isEmpty);
    });

    test('every window is exactly the requested size', () {
      for (final len in [1, 7, 8, 9, 23, 24, 25]) {
        for (final w in cutWindows(n(len), 8, minTailSamples: 1)) {
          expect(w.length, 8, reason: 'len $len');
        }
      }
    });

    test('bad window size throws', () {
      expect(() => cutWindows(n(4), 0, minTailSamples: 1), throwsArgumentError);
    });

    test(
        'the real BirdNET geometry: 10 s at 48 kHz is 3 full windows + a '
        '1 s tail', () {
      final w = cutWindows(Float32List(480000), 144000, minTailSamples: 48000);
      expect(w, hasLength(4));
      expect(cutWindows(Float32List(480000), 144000, minTailSamples: 96000),
          hasLength(3));
    });
  });

  group('sigmoid and combining windows', () {
    test('sigmoid is symmetric, bounded and stable at extremes', () {
      expect(sigmoid(0), 0.5);
      expect(sigmoid(2) + sigmoid(-2), closeTo(1, 1e-12));
      expect(sigmoid(1000), 1.0);
      expect(sigmoid(-1000), 0.0);
      expect(sigmoid(-1000).isNaN, isFalse);
    });

    test('the best window wins for each class', () {
      final p = maxProbabilities([
        Float32List.fromList([-5, 3, 0]),
        Float32List.fromList([2, -3, 0]),
      ]);
      expect(p[0], closeTo(sigmoid(2), 1e-6));
      expect(p[1], closeTo(sigmoid(3), 1e-6));
      expect(p[2], 0.5);
    });

    test('no windows gives no scores; mismatched windows throw', () {
      expect(maxProbabilities(const []), isEmpty);
      expect(
        () => maxProbabilities([Float32List(2), Float32List(3)]),
        throwsArgumentError,
      );
    });
  });

  group('labels', () {
    test('parses Scientific_Common, splitting on the first underscore', () {
      final l = parseBirdNetLabels(
        'Cardinalis cardinalis_Northern Cardinal\n'
        'Human vocal_Human vocal\n'
        'Odd name_Common_with_underscores\r\n'
        '\n'
        'NoUnderscoreHere\n',
      );
      expect(l, hasLength(4));
      expect(l[0].scientificName, 'Cardinalis cardinalis');
      expect(l[0].commonName, 'Northern Cardinal');
      expect(l[2].commonName, 'Common_with_underscores');
      expect(l[3].scientificName, '');
      expect(l[3].commonName, 'NoUnderscoreHere');
    });

    test('an empty file has no labels', () {
      expect(parseBirdNetLabels(''), isEmpty);
      expect(parseBirdNetLabels('\n\n  \n'), isEmpty);
    });
  });

  group('rankLabels', () {
    const labels = [
      BirdNetLabel('A a', 'Alpha'),
      BirdNetLabel('B b', 'Beta'),
      BirdNetLabel('C c', 'Gamma'),
      BirdNetLabel('D d', 'Delta'),
    ];

    test('best first, above the floor, at most topN', () {
      final r = rankLabels(
        Float32List.fromList([0.2, 0.9, 0.5, 0.05]),
        labels,
        topN: 2,
        floor: 0.1,
      );
      expect(r.map((x) => x.label.commonName), ['Beta', 'Gamma']);
    });

    test('ties go to the earlier label, every time', () {
      final r = rankLabels(
        Float32List.fromList([0.5, 0.5, 0.5, 0.5]),
        labels,
        topN: 4,
        floor: 0.1,
      );
      expect(r.map((x) => x.label.commonName),
          ['Alpha', 'Beta', 'Gamma', 'Delta']);
    });

    test('nothing above the floor is an empty list, not an error', () {
      expect(
        rankLabels(Float32List(4), labels, topN: 3, floor: 0.1),
        isEmpty,
      );
    });

    test('the floor is inclusive (0.5 is exact in a Float32)', () {
      final r = rankLabels(
        Float32List.fromList([0.5, 0.25, 0, 0]),
        labels,
        topN: 3,
        floor: 0.5,
      );
      expect(r.map((x) => x.label.commonName), ['Alpha']);
    });

    test('the allowed filter removes classes before ranking', () {
      final r = rankLabels(
        Float32List.fromList([0.2, 0.9, 0.5, 0.05]),
        labels,
        topN: 2,
        floor: 0.1,
        allowed: (l) => l.commonName != 'Beta',
      );
      expect(r.map((x) => x.label.commonName), ['Gamma', 'Alpha']);
    });

    test(
        'a score/label count mismatch is an error, never a silent '
        'misnaming', () {
      expect(
        () => rankLabels(Float32List(3), labels, topN: 1, floor: 0),
        throwsArgumentError,
      );
    });

    test('topN 0 gives nothing', () {
      expect(
        rankLabels(Float32List.fromList([1, 1, 1, 1]), labels,
            topN: 0, floor: 0),
        isEmpty,
      );
    });
  });

  group('analyseWav', () {
    const labels = [
      BirdNetLabel('A a', 'Alpha'),
      BirdNetLabel('B b', 'Beta'),
      BirdNetLabel('C c', 'Gamma'),
      BirdNetLabel('D d', 'Delta'),
    ];
    const settings = BirdNetSettings(
      sampleRate: 100,
      minTailSeconds: 0.03,
      topN: 3,
      scoreFloor: 0.1,
    );

    test(
        'feeds exact-size windows to the runner and ranks the best score '
        'over all windows', () async {
      final runner = FakeRunner(
        windowSamples: 100,
        script: (call, w) => call == 1
            ? Float32List.fromList([-9, 4, -9, -9])
            : Float32List.fromList([-9, -9, 1, -9]),
      );
      final r = await analyseWav(
        wav(samples: ramp(250), rate: 100), // 2.5 s -> 2 full + tail
        runner: runner,
        labels: labels,
        settings: settings,
      );
      expect(runner.windowsSeen, hasLength(3));
      expect(runner.windowsSeen.every((w) => w.length == 100), isTrue);
      expect(r.first.label.commonName, 'Beta');
      expect(r[1].label.commonName, 'Gamma');
    });

    test('resamples to the model rate before cutting', () async {
      final runner = FakeRunner(windowSamples: 100);
      await analyseWav(
        wav(samples: ramp(200), rate: 200), // 1 s at 200 Hz -> 100 @ 100 Hz
        runner: runner,
        labels: labels,
        settings: settings,
      );
      expect(runner.windowsSeen, hasLength(1));
    });

    test('too little audio: nothing is scored and the runner is not called',
        () async {
      final runner = FakeRunner(windowSamples: 100);
      final r = await analyseWav(
        wav(samples: ramp(2), rate: 100),
        runner: runner,
        labels: labels,
        settings: settings,
      );
      expect(r, isEmpty);
      expect(runner.windowsSeen, isEmpty);
    });

    test('a corrupt WAV throws a FormatException before touching the runner',
        () async {
      final runner = FakeRunner();
      await expectLater(
        analyseWav(Uint8List(100),
            runner: runner, labels: labels, settings: settings),
        throwsFormatException,
      );
      expect(runner.windowsSeen, isEmpty);
    });

    test('a runner error propagates (the provider turns it into "unavailable")',
        () async {
      final runner = FakeRunner(
        windowSamples: 100,
        script: (c, w) => throw StateError('interpreter died'),
      );
      await expectLater(
        analyseWav(wav(samples: ramp(100), rate: 100),
            runner: runner, labels: labels, settings: settings),
        throwsStateError,
      );
    });

    test('silence scores nothing above the floor', () async {
      final runner = FakeRunner(
        windowSamples: 100,
        script: (c, w) => Float32List.fromList([-9, -9, -9, -9]),
      );
      final r = await analyseWav(
        wav(samples: List.filled(100, 0.0), rate: 100),
        runner: runner,
        labels: labels,
        settings: settings,
      );
      expect(r, isEmpty);
    });

    test('a window size not matching the runner never reaches it', () async {
      // The pipeline cuts to runner.windowSamples, whatever the content says.
      final runner = FakeRunner(windowSamples: 50);
      await analyseWav(
        wav(samples: ramp(100), rate: 100),
        runner: runner,
        labels: labels,
        settings: settings,
      );
      expect(runner.windowsSeen.every((w) => w.length == 50), isTrue);
    });

    test('a long clip is bounded work: 10 s of real geometry is 4 windows',
        () async {
      final runner = FakeRunner(windowSamples: 144000, classCount: 4);
      await analyseWav(
        wav(samples: List.filled(480000, 0.01), rate: 48000),
        runner: runner,
        labels: labels,
        settings: const BirdNetSettings(
          sampleRate: 48000,
          minTailSeconds: 1.0,
          topN: 3,
          scoreFloor: 0.1,
        ),
      );
      expect(runner.windowsSeen, hasLength(4));
    });
  });

  test('math sanity: sigmoid of a typical BirdNET logit', () {
    expect(sigmoid(math.log(9)), closeTo(0.9, 1e-12));
  });
}
