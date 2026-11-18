import 'identification.dart';

/// Outcome of a successful chain run.
class ChainOutcome {
  const ChainOutcome({required this.result, required this.failuresBefore});

  final IdentificationResult result;

  /// Providers that were tried (or skipped) before one answered.
  final List<ProviderFailure> failuresBefore;

  /// True when the recording was uploaded during THIS identification: either
  /// the provider that answered uploads, or an earlier one did before failing.
  /// The privacy badge must use this and nothing else.
  bool get audioLeftDevice =>
      result.sentAudioOffDevice ||
      failuresBefore.any((f) => f.sentAudioOffDevice);
}

/// One step of a progressive identification.
class ChainProgress {
  const ChainProgress(this.outcome, {required this.isFinal});

  final ChainOutcome outcome;

  /// False for a quick answer from a lower-priority service while a
  /// higher-priority one is still working: it may be replaced. True when no
  /// better answer can still arrive.
  final bool isFinal;
}

/// What one provider did, without throwing.
class _Attempt {
  _Attempt.answered(this.result) : failure = null;
  _Attempt.failed(this.failure) : result = null;

  final IdentificationResult? result;
  final ProviderFailure? failure;

  /// An answer that ends the search: a result, or "heard no bird" from a
  /// service whose "no bird" is final. Anything else lets the next one try.
  bool decisive = false;
}

/// Result of probing every provider.
class ChainHealth {
  const ChainHealth(this.available);

  /// Provider id -> reachable.
  final Map<String, bool> available;

  bool get anyAvailable => available.values.any((v) => v);
}

/// Tries providers in order and falls through on failure.
///
/// This replaces GardenEar's single-selection logic, which returned a network
/// provider in its offline branch and never fell back when NatureLM was
/// reachable but its notebook was down.
class ProviderChain {
  ProviderChain(
    this.providers, {
    this.healthTtl = const Duration(minutes: 3),
    this.probeTimeout = const Duration(seconds: 6),
    this.perProviderTimeout = const Duration(seconds: 25),
    DateTime Function()? now,
  })  : assert(providers.isNotEmpty),
        _now = now ?? DateTime.now;

  final List<IdentificationProvider> providers;
  final Duration healthTtl;

  /// A health probe slower than this counts as "down". Render's free tier can
  /// take 30 s+ to wake, and the record button must not wait on that.
  final Duration probeTimeout;

  /// Each provider gets this long to answer before the chain moves on, so two
  /// slow services cannot leave the user watching a spinner for minutes.
  final Duration perProviderTimeout;
  final DateTime Function() _now;

  final Map<String, _CachedHealth> _health = {};

  /// Probes every provider, reusing results younger than [healthTtl].
  /// Call before enabling the record button.
  Future<ChainHealth> checkHealth({bool force = false}) async {
    final results = await Future.wait(
      providers.map((p) async => MapEntry(p.id, await _healthOf(p, force))),
    );
    return ChainHealth(Map.fromEntries(results));
  }

  /// Identifies [clip] with the first provider that answers.
  ///
  /// Throws [NoProviderAnsweredException] if none does.
  Future<ChainOutcome> identify(AudioClip clip) async {
    final failures = <ProviderFailure>[];

    for (final p in providers) {
      final cached = _freshHealth(p.id);
      if (cached == false) {
        failures.add(ProviderFailure(
          providerId: p.id,
          kind: FailureKind.unavailable,
          message: 'Health check failed recently; skipped.',
          skipped: true,
          sentAudioOffDevice: false,
        ));
        continue;
      }

      try {
        final result = await p.identify(clip).timeout(
              perProviderTimeout,
              onTimeout: () => throw ProviderException(
                FailureKind.timeout,
                '${p.label} did not answer within '
                '${perProviderTimeout.inSeconds}s.',
              ),
            );
        _health[p.id] = _CachedHealth(true, _now());
        return ChainOutcome(result: result, failuresBefore: failures);
      } on ProviderException catch (e) {
        if (e.kind == FailureKind.unavailable ||
            e.kind == FailureKind.timeout) {
          // Remember it is down so the next recording skips it quickly.
          _health[p.id] = _CachedHealth(false, _now());
        }
        failures.add(ProviderFailure(
          providerId: p.id,
          kind: e.kind,
          message: e.message,
          // Once a network provider has been handed the clip we cannot
          // prove the bytes did not leave: a connection can drop after the
          // upload. Only a provider that was never called sent nothing.
          sentAudioOffDevice: p.sendsAudioOffDevice,
        ));
        if (e.kind == FailureKind.noDetection && p.noDetectionIsFinal) {
          // The service answered: it was reachable and heard no bird. That is
          // an answer, not an outage, so we do not shop the clip around to
          // the next provider. Only "not responsive" falls through.
          _health[p.id] = _CachedHealth(true, _now());
          break;
        }
      } catch (e) {
        // A provider bug must not break the chain.
        failures.add(ProviderFailure(
          providerId: p.id,
          kind: FailureKind.badResponse,
          message: 'Unexpected error: $e',
          sentAudioOffDevice: p.sendsAudioOffDevice,
        ));
      }
    }

    throw NoProviderAnsweredException(failures);
  }

  /// Forgets what was learned about the providers, so the next probe and the
  /// next recording look again. Call when something changed that a cached
  /// "down" would hide, such as the offline model finishing its download.
  void forgetHealth() => _health.clear();

  /// Like [identify], but quick. Providers that keep the recording on the
  /// phone go first, one at a time, and if one answers nothing is uploaded.
  /// Otherwise every online provider gets the recording AT THE SAME TIME, and
  /// the first answer is emitted at once (not final) while a better-ranked
  /// provider is still working. When the best-ranked provider that can answer
  /// has answered, that is emitted as final.
  ///
  /// The recording therefore goes to every online provider that is not known
  /// to be down, and the screens must say so.
  ///
  /// Throws [NoProviderAnsweredException] when nobody gave a usable answer, or
  /// when the best-ranked provider that answered heard no bird.
  Stream<ChainProgress> identifyProgressive(AudioClip clip) async* {
    final failures = <ProviderFailure>[];

    // 1. Providers that never upload: in order, one at a time.
    var i = 0;
    for (; i < providers.length && !providers[i].sendsAudioOffDevice; i++) {
      final p = providers[i];
      final a = await _attempt(p, clip);
      if (a.result != null) {
        yield ChainProgress(
          ChainOutcome(result: a.result!, failuresBefore: [...failures]),
          isFinal: true,
        );
        return;
      }
      failures.add(a.failure!);
      if (a.decisive) throw NoProviderAnsweredException(failures);
    }

    // 2. Online providers, all at once.
    final online = providers.sublist(i);
    final results = List<_Attempt?>.filled(online.length, null);
    final pending = <int, Future<MapEntry<int, _Attempt>>>{};
    for (var k = 0; k < online.length; k++) {
      final p = online[k];
      if (_freshHealth(p.id) == false) {
        results[k] = _Attempt.failed(ProviderFailure(
          providerId: p.id,
          kind: FailureKind.unavailable,
          message: 'Health check failed recently; skipped.',
          skipped: true,
          sentAudioOffDevice: false,
        ));
      } else {
        pending[k] = _attempt(p, clip).then((a) => MapEntry(k, a));
      }
    }

    int? emitted; // index of the provisional answer already shown
    while (true) {
      // The best-ranked decisive answer, if every provider ranked above it
      // has already failed; else the first decisive answer from below.
      int? finalAt;
      int? provisionalAt;
      var blocked = false;
      for (var k = 0; k < online.length; k++) {
        final r = results[k];
        if (r == null) {
          blocked = true;
          continue;
        }
        if (r.decisive) {
          if (blocked) {
            provisionalAt ??= r.result != null ? k : null;
          } else {
            finalAt = k;
            break;
          }
        }
      }

      List<ProviderFailure> before(int upTo) => [
            ...failures,
            for (var k = 0; k < upTo; k++)
              if (results[k]?.failure != null && !results[k]!.decisive)
                results[k]!.failure!,
          ];

      if (finalAt != null) {
        final r = results[finalAt]!;
        if (r.result == null) {
          throw NoProviderAnsweredException([...before(finalAt), r.failure!]);
        }
        yield ChainProgress(
          ChainOutcome(result: r.result!, failuresBefore: before(finalAt)),
          isFinal: true,
        );
        return;
      }
      if (!blocked) {
        throw NoProviderAnsweredException([
          ...failures,
          for (final r in results)
            if (r?.failure != null) r!.failure!,
        ]);
      }
      if (provisionalAt != null && emitted != provisionalAt) {
        emitted = provisionalAt;
        yield ChainProgress(
          ChainOutcome(
            result: results[provisionalAt]!.result!,
            failuresBefore: before(provisionalAt),
          ),
          isFinal: false,
        );
      }
      final done = await Future.any(pending.values);
      results[done.key] = done.value;
      pending.remove(done.key);
    }
  }

  /// Runs one provider and never throws. Updates what the chain remembers
  /// about the provider being up or down.
  Future<_Attempt> _attempt(IdentificationProvider p, AudioClip clip) async {
    try {
      final result = await p.identify(clip).timeout(
            perProviderTimeout,
            onTimeout: () => throw ProviderException(
              FailureKind.timeout,
              '${p.label} did not answer within '
              '${perProviderTimeout.inSeconds}s.',
            ),
          );
      _health[p.id] = _CachedHealth(true, _now());
      return _Attempt.answered(result)..decisive = true;
    } on ProviderException catch (e) {
      if (e.kind == FailureKind.unavailable || e.kind == FailureKind.timeout) {
        _health[p.id] = _CachedHealth(false, _now());
      }
      final a = _Attempt.failed(ProviderFailure(
        providerId: p.id,
        kind: e.kind,
        message: e.message,
        sentAudioOffDevice: p.sendsAudioOffDevice,
      ));
      if (e.kind == FailureKind.noDetection && p.noDetectionIsFinal) {
        _health[p.id] = _CachedHealth(true, _now());
        a.decisive = true;
      }
      return a;
    } catch (e) {
      return _Attempt.failed(ProviderFailure(
        providerId: p.id,
        kind: FailureKind.badResponse,
        message: 'Unexpected error: $e',
        sentAudioOffDevice: p.sendsAudioOffDevice,
      ));
    }
  }

  bool? _freshHealth(String id) {
    final c = _health[id];
    if (c == null) return null;
    return _now().difference(c.at) < healthTtl ? c.ok : null;
  }

  Future<bool> _healthOf(IdentificationProvider p, bool force) async {
    if (!force) {
      final fresh = _freshHealth(p.id);
      if (fresh != null) return fresh;
    }
    bool ok;
    try {
      ok = await p.isAvailable().timeout(probeTimeout, onTimeout: () => false);
    } catch (_) {
      ok = false;
    }
    _health[p.id] = _CachedHealth(ok, _now());
    return ok;
  }
}

class _CachedHealth {
  const _CachedHealth(this.ok, this.at);
  final bool ok;
  final DateTime at;
}
