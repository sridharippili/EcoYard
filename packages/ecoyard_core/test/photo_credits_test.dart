import 'dart:convert';
import 'dart:io';

import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:test/test.dart';

import 'support.dart';

String creditsJson() =>
    File('${repoRoot().path}/content/photo_credits.json').readAsStringSync();

void main() {
  group('parsing', () {
    test('reads id, asset, author and licence', () {
      final c = PhotoCredits.fromJson(jsonEncode({
        'photos': [
          {
            'id': 'norcar',
            'kind': 'bird',
            'asset': 'assets/photos/bird-norcar.jpg',
            'author': 'Someone',
            'licence': 'CC BY-SA 4.0',
            'licenceUrl': 'https://example.test/l',
            'sourceUrl': 'https://example.test/s',
          },
        ],
      }));
      final p = c.forBird('norcar')!;
      expect(p.asset, 'assets/photos/bird-norcar.jpg');
      expect(p.author, 'Someone');
      expect(p.isBird, isTrue);
      expect(c.forPlant('norcar'), isNull, reason: 'kinds must not collide');
    });

    test('an unknown species has no photo, not an error', () {
      expect(PhotoCredits.empty().forBird('ghost'), isNull);
      expect(PhotoCredits.empty().isEmpty, isTrue);
    });

    test(
        'a row missing its author or licence is refused: we never ship a '
        'photo we cannot credit', () {
      for (final missing in ['id', 'kind', 'asset', 'author', 'licence']) {
        final row = {
          'id': 'x',
          'kind': 'bird',
          'asset': 'a.jpg',
          'author': 'A',
          'licence': 'CC BY 4.0',
        }..remove(missing);
        expect(
          () => PhotoCredits.fromJson(jsonEncode({
            'photos': [row]
          })),
          throwsFormatException,
          reason: 'missing $missing',
        );
      }
    });

    test('malformed JSON is refused', () {
      expect(() => PhotoCredits.fromJson('[]'), throwsFormatException);
      expect(() => PhotoCredits.fromJson('{}'), throwsFormatException);
    });
  });

  group('the photos we actually ship', () {
    late PhotoCredits credits;
    setUpAll(() => credits = PhotoCredits.fromJson(creditsJson()));

    test('every bird and every plant has one', () {
      final repo = ReferenceRepository.fromJson(realContent());
      for (final b in repo.birds) {
        expect(credits.forBird(b.id), isNotNull, reason: b.id);
      }
      for (final p in repo.plants) {
        expect(credits.forPlant(p.id), isNotNull, reason: p.id);
      }
    });

    test('every credit names an author and a licence we may ship', () {
      for (final p in credits.all) {
        expect(p.author.trim(), isNotEmpty, reason: p.id);
        expect(p.licence.trim(), isNotEmpty, reason: p.id);
        final l = p.licence.toLowerCase();
        expect(
          l.startsWith('cc0') ||
              l.startsWith('cc by') ||
              l.startsWith('public domain'),
          isTrue,
          reason: '${p.id}: "${p.licence}"',
        );
        // Non-commercial or no-derivatives licences must never slip in.
        expect(l, isNot(contains('nc')), reason: p.id);
        expect(l, isNot(contains('-nd')), reason: p.id);
      }
    });

    test('every credit points at its source page', () {
      for (final p in credits.all) {
        expect(p.sourceUrl, startsWith('https://'), reason: p.id);
      }
    });

    test('every photo file is really there, and none is huge', () {
      final root = repoRoot().path;
      for (final p in credits.all) {
        final f = File('$root/app/${p.asset}');
        expect(f.existsSync(), isTrue, reason: p.asset);
        expect(f.lengthSync(), lessThan(600 * 1024), reason: p.asset);
        expect(f.lengthSync(), greaterThan(2000), reason: p.asset);
      }
    });

    test('no two species share a photo file', () {
      final assets = credits.all.map((p) => p.asset).toList();
      expect(assets.toSet().length, assets.length);
    });
  });
}
