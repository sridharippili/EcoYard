import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Messages of every error in a report.
List<String> errorsOf(ValidationReport r) =>
    r.errors.map((e) => e.toString()).toList();

Map<String, dynamic> first(Map<String, dynamic> json, String key) =>
    (json[key] as List).first as Map<String, dynamic>;

void main() {
  group('the real content', () {
    test('passes in normal mode', () {
      final report = validateContent(realContent());
      expect(errorsOf(report), isEmpty);
      expect(report.ok, isTrue);
    });

    test('warns about drafts and pending photos in normal mode', () {
      final warnings =
          validateContent(realContent()).warnings.map((w) => w.message);
      expect(warnings.where((m) => m.contains('draft')), hasLength(6));
      expect(
          warnings.where((m) => m.contains('photo is pending')), hasLength(15));
    });

    test('fails the release gate (--strict) until reviewed and photographed',
        () {
      final report = validateContent(realContent(), strict: true);
      expect(report.ok, isFalse);
      expect(errorsOf(report).where((e) => e.contains('photo is pending')),
          hasLength(15));
      expect(
          errorsOf(report).where((e) => e.contains('"draft"')), hasLength(6));
    });
  });

  group('catches the mistakes hand-written JSON drifts into', () {
    test('a link to a plant that does not exist', () {
      final report = validateContent(withEdit('bird_plant', (j) {
        first(j, 'links')['plantId'] = 'no-such-plant';
      }));
      expect(errorsOf(report),
          contains(contains('unknown plant "no-such-plant"')));
    });

    test('a link from a bird that does not exist', () {
      final report = validateContent(withEdit('bird_plant', (j) {
        first(j, 'links')['birdId'] = 'ghost';
      }));
      expect(errorsOf(report), contains(contains('unknown bird "ghost"')));
    });

    test('a bird with zero plant links', () {
      final report = validateContent(withEdit('bird_plant', (j) {
        (j['links'] as List)
            .removeWhere((l) => (l as Map)['birdId'] == 'rthhum');
      }));
      expect(errorsOf(report),
          contains(contains('rthhum: bird has zero plant links')));
    });

    test('a duplicate link', () {
      final report = validateContent(withEdit('bird_plant', (j) {
        final links = j['links'] as List;
        links.add(Map<String, dynamic>.from(links.first as Map));
      }));
      expect(errorsOf(report), contains(contains('duplicate link')));
    });

    test('a link weight outside 1-3', () {
      final report = validateContent(withEdit('bird_plant', (j) {
        first(j, 'links')['weight'] = 5;
      }));
      expect(errorsOf(report), contains(contains('weight must be 1-3')));
    });

    test('the same alias on two different birds', () {
      final report = validateContent(withEdit('aliases', (j) {
        final rows = j['aliases'] as List;
        // Give the Blue Jay the Northern Cardinal's name.
        (rows[1] as Map)['names'] = [
          ...(rows[1] as Map)['names'] as List,
          'Northern Cardinal'
        ];
      }));
      expect(errorsOf(report),
          contains(contains('"Northern Cardinal" maps to both')));
    });

    test('the same alias differing only in case and punctuation', () {
      final report = validateContent(withEdit('aliases', (j) {
        final rows = j['aliases'] as List;
        (rows[1] as Map)['names'] = [
          ...(rows[1] as Map)['names'] as List,
          'NORTHERN-cardinal!'
        ];
      }));
      expect(errorsOf(report), contains(contains('maps to both')));
    });

    test('an alias that cleanup would change, so it could never match', () {
      final report = validateContent(withEdit('aliases', (j) {
        final rows = j['aliases'] as List;
        (rows.first as Map)['names'] = [
          ...(rows.first as Map)['names'] as List,
          'male cardinal'
        ];
      }));
      expect(errorsOf(report), contains(contains('would be altered')));
    });

    test('a bird name that is also a "not a bird" phrase', () {
      final report = validateContent(withEdit('aliases', (j) {
        final rows = j['aliases'] as List;
        (rows.first as Map)['names'] = [
          ...(rows.first as Map)['names'] as List,
          'Siren'
        ];
      }));
      expect(
          errorsOf(report), contains(contains('non-bird/no-species phrase')));
    });

    test('an alias set for a bird that does not exist', () {
      final report = validateContent(withEdit('aliases', (j) {
        (j['aliases'] as List).add({
          'taxonId': 'ghost',
          'names': ['ghost bird']
        });
      }));
      expect(errorsOf(report), contains(contains('unknown bird "ghost"')));
    });

    test('a photo marked ready with no attribution', () {
      final report = validateContent(withEdit('plants', (j) {
        first(j, 'plants')['photo'] = {
          'status': 'ready',
          'asset': 'assets/x.jpg'
        };
      }));
      expect(errorsOf(report), contains(contains('no attribution string')));
    });

    test('a photo marked ready with no asset', () {
      final report = validateContent(withEdit('plants', (j) {
        first(j, 'plants')['photo'] = {
          'status': 'ready',
          'attribution': 'A. Person, CC BY 4.0'
        };
      }));
      expect(errorsOf(report), contains(contains('no asset path')));
    });

    test('a complete photo passes', () {
      final report = validateContent(withEdit('plants', (j) {
        first(j, 'plants')['photo'] = {
          'status': 'ready',
          'asset': 'assets/plants/black-eyed-susan.jpg',
          'attribution': 'A. Person, CC BY 4.0, via Wikimedia Commons',
        };
      }));
      expect(errorsOf(report), isEmpty);
    });

    test('a schemaVersion mismatch', () {
      final report =
          validateContent(withEdit('tips', (j) => j['schemaVersion'] = 2));
      expect(errorsOf(report), contains(contains('tips.json')));
      expect(errorsOf(report), contains(contains('schemaVersion')));
    });

    test('duplicate ids', () {
      final report = validateContent(withEdit('plants', (j) {
        final plants = j['plants'] as List;
        (plants[1] as Map)['id'] = (plants[0] as Map)['id'];
      }));
      expect(errorsOf(report), contains(contains('duplicate plant id')));
    });

    test('a month with no tip', () {
      final report = validateContent(withEdit('tips', (j) {
        (j['tips'] as List)
            .removeWhere((t) => ((t as Map)['months'] as List).contains(3));
      }));
      expect(errorsOf(report), contains(contains('no tip for month(s) 3')));
    });

    test('an action pointing at a missing plant', () {
      final report = validateContent(withEdit('actions', (j) {
        first(j, 'actions')['relatedPlantIds'] = ['no-such-plant'];
      }));
      expect(errorsOf(report), contains(contains('unknown related plant')));
    });

    test('a tip pointing at a missing action', () {
      final report = validateContent(withEdit('tips', (j) {
        first(j, 'tips')['relatedActionIds'] = ['no-such-action'];
      }));
      expect(errorsOf(report), contains(contains('unknown related action')));
    });

    test('a scientific name that is not "Genus species"', () {
      final report = validateContent(withEdit('birds', (j) {
        first(j, 'birds')['scientificName'] = 'cardinalis';
      }));
      expect(errorsOf(report), contains(contains('is not "Genus species"')));
    });

    test('bloom months out of order', () {
      final report = validateContent(withEdit('plants', (j) {
        first(j, 'plants')['bloom'] = {'startMonth': 9, 'endMonth': 3};
      }));
      expect(errorsOf(report), contains(contains('bloom months')));
    });

    test('files that disagree on region', () {
      final report =
          validateContent(withEdit('tips', (j) => j['region'] = 'us-west'));
      expect(errorsOf(report), contains(contains('disagree on region')));
    });

    test('"reviewed" without a reviewer or date is an error', () {
      final report = validateContent(
          withEdit('birds', (j) => j['reviewStatus'] = 'reviewed'));
      expect(errorsOf(report), contains(contains('reviewedBy is missing')));
      expect(errorsOf(report),
          contains(contains('reviewedOn is not a YYYY-MM-DD')));
    });

    test('"reviewed" with a malformed date is an error', () {
      final report = validateContent(withEdit('birds', (j) {
        j['reviewStatus'] = 'reviewed';
        j['reviewedBy'] = 'A. Reviewer';
        j['reviewedOn'] = 'last Tuesday';
      }));
      expect(errorsOf(report),
          contains(contains('reviewedOn is not a YYYY-MM-DD')));
      expect(
          errorsOf(report), isNot(contains(contains('reviewedBy is missing'))));
    });

    test('a file that is a draft passes normally but fails --strict', () {
      final files = withEdit('birds', (j) {
        j['reviewStatus'] = 'reviewed';
        j['reviewedBy'] = 'A. Reviewer';
        j['reviewedOn'] = '2026-12-01';
      });
      expect(validateContent(files).ok, isTrue);
      // Still failing strict because the other files and photos remain.
      final strict = validateContent(files, strict: true);
      expect(
          errorsOf(strict)
              .where((e) => e.contains('birds.json') && e.contains('draft')),
          isEmpty);
    });
  });
}
