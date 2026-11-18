import 'dart:async';

import 'package:bird_audio/bird_audio.dart';
import 'package:flutter/foundation.dart';

enum BirdsPhase { idle, recording, identifying, result, failed }

/// State for the Birds tab: record -> identify -> show which service answered.
class BirdsController extends ChangeNotifier {
  BirdsController({
    required this._recorder,
    required this._chain,
    this.maxRecording = const Duration(seconds: 10),
  });

  final ClipRecorder _recorder;
  final ProviderChain _chain;

  /// Recordings stop themselves here, which also bounds upload size.
  final Duration maxRecording;

  BirdsPhase phase = BirdsPhase.idle;
  int elapsedSeconds = 0;

  /// Null until the first health probe finishes.
  ChainHealth? health;

  ChainOutcome? outcome;
  NoProviderAnsweredException? failure;

  /// True while [outcome] is a quick answer and a better-ranked service is
  /// still working. It may be replaced.
  bool refining = false;

  /// Set when the better service finished and agreed with the quick answer:
  /// the service's name.
  String? confirmedBy;

  /// Set when the better service finished and replaced the quick answer:
  /// what the quick answer had said, and who replaced it.
  String? replacedAnswer;
  String? replacedBy;

  /// Which identification run is current. An answer from an older run (the
  /// user recorded again, or tapped Done) is ignored.
  int _run = 0;

  /// Set for problems that are not about the services (permission, recorder).
  String? localError;

  bool micDenied = false;

  AudioClip? _clip;
  Timer? _autoStop;
  Timer? _ticker;
  bool _disposed = false;

  /// Whether "Try again" can reuse the last recording.
  bool get canRetry => _clip != null;

  /// Probes the services without blocking the record button. Recording is
  /// never disabled by a failed probe: a sleeping BirdNET Space reads as
  /// "down" for ~20 s but still answers a recording.
  Future<void> checkHealth({bool force = false}) async {
    final result = await _chain.checkHealth(force: force);
    if (_disposed) return;
    health = result;
    _notify();
  }

  /// Starts recording, or stops and identifies if already recording.
  Future<void> toggleRecording() async {
    switch (phase) {
      case BirdsPhase.recording:
        await _stopAndIdentify();
      case BirdsPhase.identifying:
        return;
      case BirdsPhase.idle || BirdsPhase.result || BirdsPhase.failed:
        await _startRecording();
    }
  }

  /// Runs the last recording through the chain again.
  Future<void> retry() async {
    final clip = _clip;
    if (clip == null || phase == BirdsPhase.identifying) return;
    await _identify(clip);
  }

  /// Clears the result and discards the in-memory recording.
  void dismiss() {
    _run++;
    _clip = null;
    outcome = null;
    _clearRefinement();
    failure = null;
    localError = null;
    phase = BirdsPhase.idle;
    _notify();
  }

  void _clearRefinement() {
    refining = false;
    confirmedBy = null;
    replacedAnswer = null;
    replacedBy = null;
  }

  /// Whether two answers name the same bird.
  static bool _sameBird(Detection a, Detection b) {
    final sa = a.scientificName?.trim().toLowerCase();
    final sb = b.scientificName?.trim().toLowerCase();
    if (sa != null && sb != null && sa.isNotEmpty && sa == sb) return true;
    return a.speciesText.trim().toLowerCase() ==
        b.speciesText.trim().toLowerCase();
  }

  Future<void> _startRecording() async {
    _run++;
    _clip = null;
    outcome = null;
    _clearRefinement();
    failure = null;
    localError = null;
    micDenied = false;

    try {
      if (!await _recorder.hasPermission()) {
        micDenied = true;
        phase = BirdsPhase.idle;
        _notify();
        return;
      }
      await _recorder.start();
    } catch (e) {
      localError = 'Could not start recording. Please try again.';
      phase = BirdsPhase.failed;
      _notify();
      return;
    }

    elapsedSeconds = 0;
    phase = BirdsPhase.recording;
    _autoStop = Timer(maxRecording, () => unawaited(_stopAndIdentify()));
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      elapsedSeconds++;
      _notify();
    });
    _notify();
  }

  Future<void> _stopAndIdentify() async {
    _cancelTimers();
    final AudioClip clip;
    try {
      clip = await _recorder.stop();
    } catch (e) {
      localError = 'The recording could not be read. Please try again.';
      phase = BirdsPhase.failed;
      _notify();
      return;
    }
    _clip = clip;
    await _identify(clip);
  }

  Future<void> _identify(AudioClip clip) async {
    final run = ++_run;
    phase = BirdsPhase.identifying;
    outcome = null;
    failure = null;
    localError = null;
    _clearRefinement();
    _notify();

    try {
      // A quick answer is shown the moment any service gives one; a better
      // service's answer then confirms or replaces it.
      await for (final p in _chain.identifyProgressive(clip)) {
        if (run != _run || _disposed) return;
        if (!p.isFinal) {
          outcome = p.outcome;
          refining = true;
          phase = BirdsPhase.result;
        } else {
          final shown = outcome;
          if (shown != null &&
              _sameBird(shown.result.top, p.outcome.result.top)) {
            // Same bird: keep what is on screen (and the user's ticks) and
            // just say who confirmed it.
            confirmedBy = p.outcome.result.providerLabel;
          } else {
            if (shown != null) {
              replacedAnswer = shown.result.top.speciesText;
              replacedBy = p.outcome.result.providerLabel;
            }
            outcome = p.outcome;
          }
          refining = false;
          phase = BirdsPhase.result;
        }
        _notify();
      }
      if (run != _run || _disposed) return;
      // Ended without a final answer (should not happen): stop "refining".
      refining = false;
    } on NoProviderAnsweredException catch (e) {
      if (run != _run || _disposed) return;
      refining = false;
      outcome = null;
      failure = e;
      phase = BirdsPhase.failed;
    }
    if (_disposed) return;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _cancelTimers() {
    _autoStop?.cancel();
    _ticker?.cancel();
    _autoStop = null;
    _ticker = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelTimers();
    unawaited(_recorder.cancel());
    unawaited(_recorder.dispose());
    super.dispose();
  }
}
