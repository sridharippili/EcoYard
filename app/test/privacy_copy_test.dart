import 'package:bird_audio/bird_audio.dart';
import 'package:ecoyard/features/birds/privacy_copy.dart';
import 'package:flutter_test/flutter_test.dart';

IdentificationResult result(String id, String label, {bool sentOff = true}) =>
    IdentificationResult(
      providerId: id,
      sentAudioOffDevice: sentOff,
      providerLabel: label,
      detections: const [Detection(speciesText: 'Blue Jay')],
    );

/// An outcome where [id] answered after [before] were tried.
ChainOutcome outcome(
  String id,
  String label, {
  bool sentOff = true,
  List<ProviderFailure> before = const [],
}) => ChainOutcome(
  result: result(id, label, sentOff: sentOff),
  failuresBefore: before,
);

ProviderFailure failure(
  String id, {
  bool sentOff = true,
  bool skipped = false,
}) => ProviderFailure(
  providerId: id,
  kind: FailureKind.unavailable,
  message: skipped ? 'skipped' : 'down',
  sentAudioOffDevice: sentOff,
  skipped: skipped,
);

void main() {
  group('privacyBadge when the audio went online', () {
    test('there is no per-result line: it is explained once, in Settings and '
        'the policy', () {
      expect(privacyBadge(outcome('naturelm', 'NatureLM')), isNull);
      expect(privacyBadge(outcome('birdnet', 'BirdNET')), isNull);
    });

    test('a failed first attempt that sent the audio still gets no '
        '"not sent" claim', () {
      final o = outcome(
        'birdnet-local',
        'BirdNET on this phone',
        sentOff: false,
        before: [failure('naturelm')],
      );
      expect(privacyBadge(o), isNull);
    });
  });

  group('privacyBadge for the on-device model', () {
    test('claims nothing was sent only when nothing was', () {
      final s = privacyBadge(
        outcome('birdnet-local', 'BirdNET on this phone', sentOff: false),
      );
      expect(
        s,
        'Identified on this phone. The recording was not sent '
        'anywhere.',
      );
    });

    test(
      'a local answer AFTER a network attempt admits the audio was sent',
      () {
        final s = privacyBadge(
          outcome(
            'birdnet-local',
            'BirdNET on this phone',
            sentOff: false,
            before: [failure('naturelm')],
          ),
        );
        // The audio left the phone, so there is no "not sent" claim at all.
        expect(s, isNull);
      },
    );

    test(
      'a network provider that was only skipped does not spoil the claim',
      () {
        final s = privacyBadge(
          outcome(
            'birdnet-local',
            'BirdNET on this phone',
            sentOff: false,
            before: [failure('naturelm', sentOff: false, skipped: true)],
          ),
        );
        expect(s, contains('not sent anywhere'));
      },
    );
  });

  group('fallbackNote', () {
    test('null when the first provider answered', () {
      final o = ChainOutcome(
        result: result('naturelm', 'NatureLM'),
        failuresBefore: const [],
      );
      expect(fallbackNote(o), isNull);
    });

    test('says NatureLM did not answer when it was tried and failed', () {
      final o = ChainOutcome(
        result: result('birdnet', 'BirdNET'),
        failuresBefore: const [
          ProviderFailure(
            providerId: 'naturelm',
            sentAudioOffDevice: true,
            kind: FailureKind.unavailable,
            message: 'down',
          ),
        ],
      );
      expect(fallbackNote(o), 'NatureLM did not answer, so BirdNET answered.');
    });

    test(
      'says "was not available" when it was skipped by the health check',
      () {
        final o = ChainOutcome(
          result: result('birdnet', 'BirdNET'),
          failuresBefore: const [
            ProviderFailure(
              providerId: 'naturelm',
              sentAudioOffDevice: true,
              kind: FailureKind.unavailable,
              message: 'skipped',
              skipped: true,
            ),
          ],
        );
        expect(
          fallbackNote(o),
          'NatureLM was not available, so BirdNET answered.',
        );
      },
    );
  });
}
