import 'dart:typed_data';

import 'package:bird_audio/bird_audio.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a provider does on this run.
enum Behaviour {
  answers,
  unavailable,
  timeoutLike,
  rejected,
  heardNothing,
  bug
}

class P implements IdentificationProvider {
  P(this.id, this.sendsAudioOffDevice, this.behaviour,
      {this.noDetectionIsFinal = true});

  @override
  final String id;
  @override
  final bool sendsAudioOffDevice;
  @override
  final bool noDetectionIsFinal;
  final Behaviour behaviour;

  @override
  String get label => id;

  var identifyCalls = 0;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<IdentificationResult> identify(AudioClip clip) async {
    identifyCalls++;
    switch (behaviour) {
      case Behaviour.answers:
        return IdentificationResult(
          providerId: id,
          providerLabel: id,
          sentAudioOffDevice: sendsAudioOffDevice,
          detections: const [Detection(speciesText: 'Northern Cardinal')],
        );
      case Behaviour.unavailable:
        throw const ProviderException(FailureKind.unavailable, 'down');
      case Behaviour.timeoutLike:
        throw const ProviderException(FailureKind.timeout, 'slow');
      case Behaviour.rejected:
        throw const ProviderException(FailureKind.rejected, 'HTTP 500');
      case Behaviour.heardNothing:
        throw const ProviderException(FailureKind.noDetection, 'nothing');
      case Behaviour.bug:
        throw StateError('provider bug');
    }
  }
}

final clip = AudioClip(bytes: Uint8List.fromList([1, 2, 3]));

void main() {
  group('the "audio stayed on the phone" claim', () {
    test(
        'every order and every failure: the claim is true only when no '
        'network provider was reached', () async {
      final behaviours = Behaviour.values;
      var claims = 0;
      var runs = 0;

      // Every arrangement of (local, network A, network B), every behaviour.
      for (final order in [
        [0, 1, 2],
        [1, 0, 2],
        [1, 2, 0],
      ]) {
        for (final bLocal in behaviours) {
          for (final bA in behaviours) {
            for (final bB in behaviours) {
              final local =
                  P('local', false, bLocal, noDetectionIsFinal: false);
              final a = P('netA', true, bA);
              final b = P('netB', true, bB);
              final all = [local, a, b];
              final chain = ProviderChain([for (final i in order) all[i]]);
              runs++;
              try {
                final outcome = await chain.identify(clip);
                final answeredLocally = outcome.result.providerId == 'local';
                final networkTried = [a, b].any((p) => p.identifyCalls > 0);

                if (!outcome.audioLeftDevice) {
                  claims++;
                  // The claim is only ever made when BOTH are true.
                  expect(answeredLocally, isTrue,
                      reason: 'claimed "not sent" but $order/$bLocal/$bA/$bB '
                          'was answered by ${outcome.result.providerId}');
                  expect(networkTried, isFalse,
                      reason: 'claimed "not sent" but a network provider '
                          'already had the clip ($order/$bLocal/$bA/$bB)');
                } else {
                  // Whenever we admit it was sent, something really did send
                  // it or answer from the network.
                  expect(
                    networkTried || outcome.result.sentAudioOffDevice,
                    isTrue,
                  );
                }
              } on NoProviderAnsweredException {
                // No answer at all: nothing to claim.
              }
            }
          }
        }
      }
      expect(runs, 648);
      expect(claims, greaterThan(0), reason: 'the claim must be reachable');
    });

    test('local answers first: no network provider is even asked', () async {
      final local =
          P('local', false, Behaviour.answers, noDetectionIsFinal: false);
      final net = P('net', true, Behaviour.answers);
      final outcome = await ProviderChain([local, net]).identify(clip);
      expect(net.identifyCalls, 0);
      expect(outcome.audioLeftDevice, isFalse);
    });

    test('local hears nothing: online gets a turn and the claim is dropped',
        () async {
      final local =
          P('local', false, Behaviour.heardNothing, noDetectionIsFinal: false);
      final net = P('net', true, Behaviour.answers);
      final outcome = await ProviderChain([local, net]).identify(clip);
      expect(net.identifyCalls, 1);
      expect(outcome.result.providerId, 'net');
      expect(outcome.audioLeftDevice, isTrue);
    });

    test('an online service hearing nothing still ends it', () async {
      final net = P('net', true, Behaviour.heardNothing);
      final other = P('net2', true, Behaviour.answers);
      await expectLater(
        ProviderChain([net, other]).identify(clip),
        throwsA(isA<NoProviderAnsweredException>()),
      );
      expect(other.identifyCalls, 0);
    });

    test(
        'a network provider skipped by a cached health check did not send '
        'the audio', () async {
      final net = P('net', true, Behaviour.unavailable);
      final local =
          P('local', false, Behaviour.answers, noDetectionIsFinal: false);
      final chain = ProviderChain([net, local]);
      await chain.identify(clip); // marks net down
      final second = await chain.identify(clip);
      expect(second.failuresBefore.single.skipped, isTrue);
      expect(second.failuresBefore.single.sentAudioOffDevice, isFalse);
      expect(second.audioLeftDevice, isFalse,
          reason: 'a provider that was never called sent nothing');
    });

    test(
        'a network provider that was tried counts as sent, however it '
        'failed: a connection can drop after the upload', () async {
      final local = P(
        'local',
        false,
        Behaviour.answers,
        noDetectionIsFinal: false,
      );
      for (final how in [
        Behaviour.unavailable,
        Behaviour.timeoutLike,
        Behaviour.rejected,
        Behaviour.bug,
      ]) {
        final net = P('net', true, how);
        final outcome = await ProviderChain([net, local]).identify(clip);
        expect(outcome.result.providerId, 'local');
        expect(outcome.audioLeftDevice, isTrue, reason: '$how');
      }
    });
  });
}
