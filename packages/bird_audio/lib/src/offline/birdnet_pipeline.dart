import 'dart:math' as math;
import 'dart:typed_data';

import 'model_runner.dart';
import 'wav.dart';

/// One line of BirdNET's label file: `Scientific name_Common name`.
class BirdNetLabel {
  const BirdNetLabel(this.scientificName, this.commonName);
  final String scientificName;
  final String commonName;
}

/// Parses BirdNET's label file. Splits each line on the FIRST underscore
/// (common names can contain underscores in other languages). Blank lines are
/// ignored; a line without an underscore is kept as a common name only.
List<BirdNetLabel> parseBirdNetLabels(String text) => [
      for (final raw in text.split(RegExp(r'\r?\n')))
        if (raw.trim().isNotEmpty)
          () {
            final line = raw.trim();
            final i = line.indexOf('_');
            return i < 0
                ? BirdNetLabel('', line)
                : BirdNetLabel(line.substring(0, i), line.substring(i + 1));
          }(),
    ];

/// Resamples by linear interpolation. Good enough for the 44.1 -> 48 kHz case
/// a phone may hand us; the recorder is asked for 48 kHz in the first place.
Float32List resampleLinear(Float32List input, int from, int to) {
  if (from <= 0 || to <= 0) throw ArgumentError('Sample rates must be > 0');
  if (from == to || input.isEmpty) return input;
  final outLength = (input.length * to / from).round();
  final out = Float32List(outLength);
  final step = from / to;
  for (var i = 0; i < outLength; i++) {
    final pos = i * step;
    final j = pos.floor();
    if (j >= input.length - 1) {
      out[i] = input[input.length - 1];
    } else {
      final frac = pos - j;
      out[i] = input[j] * (1 - frac) + input[j + 1] * frac;
    }
  }
  return out;
}

/// Cuts audio into model windows of exactly [windowSamples].
///
/// Full windows first; a remainder of at least [minTailSamples] becomes one
/// more window, padded with silence; a shorter remainder is dropped. Audio
/// shorter than one window is padded into a single window if it is at least
/// [minTailSamples] long; otherwise there is nothing to score (empty list).
List<Float32List> cutWindows(
  Float32List samples,
  int windowSamples, {
  required int minTailSamples,
}) {
  if (windowSamples <= 0) throw ArgumentError('windowSamples must be > 0');
  final out = <Float32List>[];
  var start = 0;
  while (start + windowSamples <= samples.length) {
    out.add(Float32List.sublistView(samples, start, start + windowSamples));
    start += windowSamples;
  }
  final tail = samples.length - start;
  if (tail > 0 && tail >= minTailSamples) {
    out.add(
      Float32List(windowSamples)..setRange(0, tail, samples, start),
    );
  }
  return out;
}

double sigmoid(double x) {
  // Stable for large magnitudes in both directions.
  if (x >= 0) return 1 / (1 + math.exp(-x));
  final e = math.exp(x);
  return e / (1 + e);
}

/// Per class, the highest probability over all windows: a bird that sang in
/// any 3 s window counts.
Float32List maxProbabilities(List<Float32List> logitsPerWindow) {
  if (logitsPerWindow.isEmpty) return Float32List(0);
  final n = logitsPerWindow.first.length;
  final out = Float32List(n);
  for (final w in logitsPerWindow) {
    if (w.length != n) throw ArgumentError('Windows have different sizes');
    for (var i = 0; i < n; i++) {
      final p = sigmoid(w[i]);
      if (p > out[i]) out[i] = p;
    }
  }
  return out;
}

/// One ranked candidate from the offline model.
class ScoredLabel {
  const ScoredLabel(this.label, this.probability);
  final BirdNetLabel label;
  final double probability;
}

/// The best [topN] classes at or above [floor], best first; ties by label
/// order so the result never depends on sort stability.
List<ScoredLabel> rankLabels(
  Float32List probabilities,
  List<BirdNetLabel> labels, {
  required int topN,
  required double floor,
  bool Function(BirdNetLabel)? allowed,
}) {
  if (probabilities.length != labels.length) {
    throw ArgumentError(
      'Model gives ${probabilities.length} scores but there are '
      '${labels.length} labels',
    );
  }
  final idx = [
    for (var i = 0; i < labels.length; i++)
      if (probabilities[i] >= floor && (allowed?.call(labels[i]) ?? true)) i,
  ]..sort((a, b) {
      final c = probabilities[b].compareTo(probabilities[a]);
      return c != 0 ? c : a.compareTo(b);
    });
  return [
    for (final i in idx.take(topN)) ScoredLabel(labels[i], probabilities[i]),
  ];
}

/// Settings for one analysis, read from content (never hard-coded in Dart).
class BirdNetSettings {
  const BirdNetSettings({
    required this.sampleRate,
    required this.minTailSeconds,
    required this.topN,
    required this.scoreFloor,
  });

  final int sampleRate;
  final double minTailSeconds;
  final int topN;
  final double scoreFloor;
}

/// WAV bytes -> ranked candidates, using [runner] for the model itself.
/// Everything but the runner is pure Dart and unit-tested.
Future<List<ScoredLabel>> analyseWav(
  Uint8List wavBytes, {
  required BirdModelRunner runner,
  required List<BirdNetLabel> labels,
  required BirdNetSettings settings,
  bool Function(BirdNetLabel)? allowed,
}) async {
  final pcm = decodeWav(wavBytes);
  final samples = resampleLinear(
    pcm.samples,
    pcm.sampleRate,
    settings.sampleRate,
  );
  final windows = cutWindows(
    samples,
    runner.windowSamples,
    minTailSamples: (settings.minTailSeconds * settings.sampleRate).round(),
  );
  if (windows.isEmpty) return const [];
  final logits = <Float32List>[];
  for (final w in windows) {
    logits.add(await runner.logitsFor(w));
  }
  return rankLabels(
    maxProbabilities(logits),
    labels,
    topN: settings.topN,
    floor: settings.scoreFloor,
    allowed: allowed,
  );
}
