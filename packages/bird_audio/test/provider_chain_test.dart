import 'dart:typed_data';

import 'package:bird_audio/bird_audio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scriptable provider. No network, no mocks library.
class FakeProvider implements IdentificationProvider {
  FakeProvider(
    this.id, {
    this.available = true,
    this.availabilityThrows = false,
    this.sendsAudioOffDevice = true,
    this.noDetectionIsFinal = true,
    Object? outcome,
  }) : outcome = outcome ?? _answer(id, sendsAudioOffDevice);

  @override
  final String id;
  @override
  String get label => id.toUpperCase();

  bool available;
  bool availabilityThrows;
  @override
  final bool sendsAudioOffDevice;
  @override
  final bool noDetectionIsFinal;

  /// Either an [IdentificationResult] to return, or an object to throw.
  Object outcome;

  int availabilityCalls = 0;
  int identifyCalls = 0;

  static IdentificationResult _answer(String id, bool sendsOff) =>
      IdentificationResult(
        providerId: id,
        providerLabel: id.toUpperCase(),
        sentAudioOffDevice: sendsOff,
        detections: const [Detection(speciesText: 'Northern Cardinal')],
      );

  @override
  Future<bool> isAvailable() async {
    availabilityCalls++;
    if (availabilityThrows) throw StateError('probe blew up');
    return available;
  }

  @override
  Future<IdentificationResult> identify(AudioClip clip) async {
    identifyCalls++;
    final o = outcome;
    if (o is IdentificationResult) return o;
    throw o;
  }
}

/// Answers, but only after [delay]. Used to exercise the timeouts.
class _SlowProvider implements IdentificationProvider {
  _SlowProvider(this.id, this.delay);

  @override
  final String id;
  final Duration delay;

  @override
  bool get sendsAudioOffDevice => true;
  @override
  bool get noDetectionIsFinal => true;

  @override
  String get label => id.toUpperCase();

  @override
  Future<bool> isAvailable() async {
    await Future<void>.delayed(delay);
    return true;
  }

  @override
  Future<IdentificationResult> identify(AudioClip clip) async {
    await Future<void>.delayed(delay);
    return FakeProvider._answer(id, true);
  }
}

final clip = AudioClip(bytes: Uint8List.fromList([1, 2, 3]));

void main() {
  late DateTime clock;
  DateTime now() => clock;

  setUp(() => clock = DateTime(2026, 11, 14, 12));

  ProviderChain chainOf(List<FakeProvider> ps) =>
      ProviderChain(ps, healthTtl: const Duration(minutes: 3), now: now);

  group('identify', () {
    test('first provider answers; the rest are never called', () async {
      final nature = FakeProvider('naturelm');
      final birdnet = FakeProvider('birdnet');

      final outcome = await chainOf([nature, birdnet]).identify(clip);

      expect(outcome.result.providerId, 'naturelm');
      expect(outcome.failuresBefore, isEmpty);
      expect(birdnet.identifyCalls, 0);
    });

    test('NatureLM unreachable -> falls through to BirdNET online', () async {
      final nature = FakeProvider('naturelm',
          outcome: const ProviderException(
              FailureKind.unavailable, 'NatureLM is not running'));
      final birdnet = FakeProvider('birdnet');

      final outcome = await chainOf([nature, birdnet]).identify(clip);

      expect(outcome.result.providerId, 'birdnet');
      expect(outcome.failuresBefore, hasLength(1));
      expect(outcome.failuresBefore.single.providerId, 'naturelm');
      expect(outcome.failuresBefore.single.kind, FailureKind.unavailable);
    });

    test('NatureLM answers with a server error -> still falls through',
        () async {
      final nature = FakeProvider('naturelm',
          outcome: const ProviderException(FailureKind.rejected, 'HTTP 502'));
      final birdnet = FakeProvider('birdnet');

      final outcome = await chainOf([nature, birdnet]).identify(clip);

      expect(outcome.result.providerId, 'birdnet');
      expect(outcome.failuresBefore.single.kind, FailureKind.rejected);
    });

    test('a provider bug (unexpected exception) does not break the chain',
        () async {
      final nature =
          FakeProvider('naturelm', outcome: StateError('parser exploded'));
      final birdnet = FakeProvider('birdnet');

      final outcome = await chainOf([nature, birdnet]).identify(clip);

      expect(outcome.result.providerId, 'birdnet');
      expect(outcome.failuresBefore.single.kind, FailureKind.badResponse);
    });

    test('everyone unreachable -> honest error, looksOffline', () async {
      const down = ProviderException(FailureKind.unavailable, 'no route');
      const slow = ProviderException(FailureKind.timeout, 'timed out');
      final chain = chainOf([
        FakeProvider('naturelm', outcome: down),
        FakeProvider('birdnet', outcome: slow),
      ]);

      await expectLater(
        chain.identify(clip),
        throwsA(isA<NoProviderAnsweredException>()
            .having((e) => e.failures.length, 'failures', 2)
            .having((e) => e.looksOffline, 'looksOffline', isTrue)),
      );
    });

    test('NatureLM answers "heard nothing" -> final; BirdNET is NOT tried',
        () async {
      final nature = FakeProvider('naturelm',
          outcome: const ProviderException(
              FailureKind.noDetection, 'No bird heard'));
      final birdnet = FakeProvider('birdnet');

      await expectLater(
        chainOf([nature, birdnet]).identify(clip),
        throwsA(isA<NoProviderAnsweredException>()
            .having((e) => e.heardNothing, 'heardNothing', isTrue)
            .having((e) => e.looksOffline, 'looksOffline', isFalse)),
      );
      expect(birdnet.identifyCalls, 0);
    });

    test('a provider slower than the budget is abandoned for the next one',
        () async {
      final slow = _SlowProvider('naturelm', const Duration(milliseconds: 400));
      final birdnet = FakeProvider('birdnet');
      final chain = ProviderChain(
        [slow, birdnet],
        perProviderTimeout: const Duration(milliseconds: 40),
        now: now,
      );

      final outcome = await chain.identify(clip);

      expect(outcome.result.providerId, 'birdnet');
      expect(outcome.failuresBefore.single.kind, FailureKind.timeout);
    });

    test('a health probe slower than probeTimeout counts as down', () async {
      final slow = _SlowProvider('naturelm', const Duration(milliseconds: 400));
      final chain = ProviderChain(
        [slow],
        probeTimeout: const Duration(milliseconds: 40),
        now: now,
      );

      final health = await chain.checkHealth();

      expect(health.available['naturelm'], isFalse);
    });

    test('reached but heard no bird -> NOT reported as offline', () async {
      final chain = chainOf([
        FakeProvider('naturelm',
            outcome: const ProviderException(
                FailureKind.unavailable, 'NatureLM is not running')),
        FakeProvider('birdnet',
            outcome: const ProviderException(
                FailureKind.noDetection, 'No species detected')),
      ]);

      await expectLater(
        chain.identify(clip),
        throwsA(isA<NoProviderAnsweredException>()
            .having((e) => e.looksOffline, 'looksOffline', isFalse)),
      );
    });
  });

  group('health cache', () {
    test('checkHealth reuses a fresh result, re-probes after the TTL',
        () async {
      final nature = FakeProvider('naturelm');
      final chain = chainOf([nature]);

      await chain.checkHealth();
      await chain.checkHealth();
      expect(nature.availabilityCalls, 1);

      clock = clock.add(const Duration(minutes: 4));
      await chain.checkHealth();
      expect(nature.availabilityCalls, 2);
    });

    test('force: true always re-probes', () async {
      final nature = FakeProvider('naturelm');
      final chain = chainOf([nature]);

      await chain.checkHealth();
      await chain.checkHealth(force: true);

      expect(nature.availabilityCalls, 2);
    });

    test('a probe that throws counts as unavailable', () async {
      final nature = FakeProvider('naturelm', availabilityThrows: true);
      final chain = chainOf([nature]);

      final health = await chain.checkHealth();

      expect(health.available['naturelm'], isFalse);
      expect(health.anyAvailable, isFalse);
    });

    test('anyAvailable is true when only the fallback is reachable', () async {
      final chain = chainOf([
        FakeProvider('naturelm', available: false),
        FakeProvider('birdnet'),
      ]);

      final health = await chain.checkHealth();

      expect(health.available, {'naturelm': false, 'birdnet': true});
      expect(health.anyAvailable, isTrue);
    });

    test('a provider found down is skipped on the next recording, until TTL',
        () async {
      final nature = FakeProvider('naturelm',
          outcome: const ProviderException(FailureKind.unavailable, 'down'));
      final birdnet = FakeProvider('birdnet');
      final chain = chainOf([nature, birdnet]);

      await chain.identify(clip);
      expect(nature.identifyCalls, 1);

      final second = await chain.identify(clip);
      expect(nature.identifyCalls, 1, reason: 'skipped, not retried');
      expect(second.failuresBefore.single.skipped, isTrue);

      clock = clock.add(const Duration(minutes: 4));
      await chain.identify(clip);
      expect(nature.identifyCalls, 2, reason: 'TTL expired, tried again');
    });

    test('a failing health probe makes identify skip that provider', () async {
      final nature = FakeProvider('naturelm', available: false);
      final birdnet = FakeProvider('birdnet');
      final chain = chainOf([nature, birdnet]);

      await chain.checkHealth();
      final outcome = await chain.identify(clip);

      expect(nature.identifyCalls, 0);
      expect(outcome.result.providerId, 'birdnet');
    });

    test('"no bird heard" does not mark a provider unhealthy', () async {
      final nature = FakeProvider('naturelm',
          outcome: const ProviderException(
              FailureKind.noDetection, 'Heard nothing'));
      final birdnet = FakeProvider('birdnet');
      final chain = chainOf([nature, birdnet]);

      await expectLater(
          chain.identify(clip), throwsA(isA<NoProviderAnsweredException>()));
      await expectLater(
          chain.identify(clip), throwsA(isA<NoProviderAnsweredException>()));

      expect(nature.identifyCalls, 2, reason: 'asked again, not skipped');
      expect(birdnet.identifyCalls, 0, reason: 'an answer is final');
    });

    test('a later success clears an earlier failure', () async {
      final nature = FakeProvider('naturelm',
          outcome: const ProviderException(FailureKind.unavailable, 'down'));
      final birdnet = FakeProvider('birdnet');
      final chain = chainOf([nature, birdnet]);

      await chain.identify(clip); // nature marked down
      nature
        ..outcome = FakeProvider._answer('naturelm', true)
        ..available = true;

      await chain.checkHealth(force: true); // notebook came back
      final outcome = await chain.identify(clip);

      expect(outcome.result.providerId, 'naturelm');
    });
  });
}
