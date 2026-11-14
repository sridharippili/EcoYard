import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late ReferenceRepository repo;

  setUpAll(() => repo = ReferenceRepository.fromJson(realContent()));

  group('the real content', () {
    test('has the vertical slice: 10 birds, 15 plants', () {
      expect(repo.birds, hasLength(10));
      expect(repo.plants, hasLength(15));
      expect(repo.actions, isNotEmpty);
      expect(repo.tips, hasLength(12));
    });

    test('is still a draft, so release must be blocked', () {
      expect(repo.reviewStatus, ReviewStatus.draft);
    });

    test('every bird has at least one plant link', () {
      for (final b in repo.birds) {
        expect(repo.linksForBird(b.id), isNotEmpty, reason: b.id);
      }
    });

    test('looks things up by id', () {
      expect(repo.birdById('norcar')!.commonName, 'Northern Cardinal');
      expect(repo.plantById('white-oak')!.scientificName, 'Quercus alba');
      expect(repo.actionById('add-water-source')!.costTier, CostTier.free);
      expect(repo.birdById('nope'), isNull);
    });

    test('linksForBird lists the strongest links first, in a stable order', () {
      final links = repo.linksForBird('amegfi');
      expect(links.map((l) => l.weight), [3, 3, 2]);
      expect(links.first.plantId, 'black-eyed-susan');
      expect(links[1].plantId, 'purple-coneflower');
    });

    test('linksForPlant finds the birds a plant supports', () {
      final birds = repo.linksForPlant('white-oak').map((l) => l.birdId);
      expect(birds, containsAll(['blujay', 'bkcchi', 'tuftit', 'whbnut']));
    });

    test('a tip exists for every month', () {
      for (var m = 1; m <= 12; m++) {
        expect(repo.tipForMonth(m), isNotNull, reason: 'month $m');
      }
      expect(repo.tipForMonth(10)!.text, contains('leaves'));
      expect(repo.tipForMonth(13), isNull);
    });

    test('plants carry the fields the Plant Finder will filter on', () {
      final p = repo.plantById('purple-coneflower')!;
      expect(p.nativity, Nativity.easternUs);
      expect(p.sun, [SunExposure.full]);
      expect(p.spaces, contains(SpaceType.containers));
      expect(p.photo.status, PhotoStatus.pending);
    });
  });

  group('rejecting bad content', () {
    test('an unsupported schemaVersion is refused, naming the file', () {
      final files = withEdit('plants', (j) => j['schemaVersion'] = 2);
      expect(
        () => ReferenceRepository.fromJson(files),
        throwsA(isA<ContentFormatException>()
            .having((e) => e.file, 'file', 'plants.json')
            .having((e) => e.message, 'message', contains('schemaVersion'))),
      );
    });

    test('invalid JSON is refused', () {
      final c = realContent();
      final files = ContentFiles(
        birds: '{ not json',
        plants: c.plants,
        birdPlant: c.birdPlant,
        actions: c.actions,
        tips: c.tips,
        aliases: c.aliases,
      );
      expect(() => ReferenceRepository.fromJson(files),
          throwsA(isA<ContentFormatException>()));
    });

    test('an unknown enum value is refused, listing the allowed ones', () {
      final files = withEdit('plants', (j) {
        ((j['plants'] as List).first as Map)['water'] = 'swampy';
      });
      expect(
        () => ReferenceRepository.fromJson(files),
        throwsA(isA<ContentFormatException>().having(
            (e) => e.message, 'message', contains('low, medium, high'))),
      );
    });

    test('a missing required field is refused', () {
      final files = withEdit('birds', (j) {
        ((j['birds'] as List).first as Map).remove('commonName');
      });
      expect(() => ReferenceRepository.fromJson(files),
          throwsA(isA<ContentFormatException>()));
    });
  });
}
