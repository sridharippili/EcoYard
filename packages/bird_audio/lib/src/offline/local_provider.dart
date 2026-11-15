import 'dart:async';

import '../identification.dart';
import 'birdnet_pipeline.dart';
import 'model_runner.dart';

/// Identifies a recording with the downloaded BirdNET model, on the phone.
///
/// Nothing leaves the device ([sendsAudioOffDevice] is false), so a result
/// from here lets the UI say so honestly.
///
/// Failure policy, so the chain behaves predictably:
/// - model not downloaded, cannot load, or the runner misbehaves ->
///   `FailureKind.unavailable`, which marks it down and falls through;
/// - audio it cannot read -> `badResponse`, also a fall-through;
/// - heard nothing -> `noDetection`, and [noDetectionIsFinal] is FALSE, so the
///   online services still get a turn. A quiet phone model is not an answer.
class BirdNetLocalProvider implements IdentificationProvider {
  BirdNetLocalProvider({
    required this.loadRunner,
    required this.loadLabels,
    required this.settings,
    required this.isModelReady,
    this.allowed,
  });

  /// Opens the model. Called once, lazily, inside [identify]: never in
  /// [isAvailable], where a cold 52 MB load would blow the probe timeout.
  final Future<BirdModelRunner> Function() loadRunner;

  final Future<List<BirdNetLabel>> Function() loadLabels;
  final BirdNetSettings settings;

  /// Cheap check: are the files on disk, with the right size?
  final Future<bool> Function() isModelReady;

  /// Optional species filter (a regional list, say). Null means every label
  /// the model knows is allowed.
  final bool Function(BirdNetLabel)? allowed;

  @override
  String get id => 'birdnet-local';

  @override
  String get label => 'BirdNET on this phone';

  @override
  bool get sendsAudioOffDevice => false;

  @override
  bool get noDetectionIsFinal => false;

  BirdModelRunner? _runner;
  List<BirdNetLabel>? _labels;
  Future<void>? _loading;

  @override
  Future<bool> isAvailable() async {
    try {
      return await isModelReady();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<IdentificationResult> identify(AudioClip clip) async {
    if (!await isAvailable()) {
      throw const ProviderException(
        FailureKind.unavailable,
        'The offline model is not downloaded.',
      );
    }
    await _ensureLoaded();
    final runner = _runner!;

    final List<ScoredLabel> ranked;
    try {
      ranked = await analyseWav(
        clip.bytes,
        runner: runner,
        labels: _labels!,
        settings: settings,
        allowed: allowed,
      );
    } on FormatException catch (e) {
      throw ProviderException(
        FailureKind.badResponse,
        'The recording could not be read on this phone (${e.message}).',
      );
    } catch (e) {
      // A broken interpreter must mark the provider down, not be retried on
      // every recording.
      await close();
      throw ProviderException(
        FailureKind.unavailable,
        'The offline model stopped working ($e).',
      );
    }

    if (ranked.isEmpty) {
      throw const ProviderException(
        FailureKind.noDetection,
        'The phone model heard no bird in this recording.',
      );
    }

    return IdentificationResult(
      providerId: id,
      providerLabel: label,
      sentAudioOffDevice: false,
      detections: [
        for (final s in ranked)
          Detection(
            speciesText: s.label.commonName,
            scientificName:
                s.label.scientificName.isEmpty ? null : s.label.scientificName,
            confidence: s.probability,
          ),
      ],
    );
  }

  /// Loads the model and labels once, even if two recordings race.
  Future<void> _ensureLoaded() async {
    if (_runner != null && _labels != null) return;
    final pending = _loading;
    if (pending != null) return pending;
    final started = _load();
    _loading = started;
    try {
      await started;
    } finally {
      _loading = null;
    }
  }

  Future<void> _load() async {
    try {
      final labels = _labels ?? await loadLabels();
      final runner = _runner ?? await loadRunner();
      _labels = labels;
      _runner = runner;
    } catch (e) {
      await close();
      throw ProviderException(
        FailureKind.unavailable,
        'The offline model could not be opened ($e).',
      );
    }
  }

  /// Frees the model. Called when it is removed, when the data is erased and
  /// after a failure. Safe to call twice.
  Future<void> close() async {
    final r = _runner;
    _runner = null;
    _labels = null;
    if (r != null) {
      try {
        await r.close();
      } catch (_) {}
    }
  }
}
