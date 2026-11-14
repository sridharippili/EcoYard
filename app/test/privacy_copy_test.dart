import 'package:bird_audio/bird_audio.dart';
import 'package:ecoyard/features/birds/privacy_copy.dart';
import 'package:flutter_test/flutter_test.dart';

IdentificationResult result(String id, String label) => IdentificationResult(
  providerId: id,
  providerLabel: label,
  detections: const [Detection(speciesText: 'Blue Jay')],
);

void main() {
  group('privacyBadge', () {
    test('names the provider that actually answered', () {
      expect(
        privacyBadge(result('naturelm', 'NatureLM')),
        contains('sent to NatureLM'),
      );
      expect(
        privacyBadge(result('birdnet', 'BirdNET')),
        contains('sent to BirdNET'),
      );
    });

    test('says it was identified online, never "on your phone"', () {
      final s = privacyBadge(result('naturelm', 'NatureLM'));
      expect(s, startsWith('Identified online'));
      expect(s.toLowerCase(), isNot(contains('on your phone')));
    });

    test('does not claim "not kept" until the services are audited', () {
      final s = privacyBadge(result('birdnet', 'BirdNET')).toLowerCase();
      expect(s, isNot(contains('not kept')));
      expect(s, isNot(contains('deleted')));
    });
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
