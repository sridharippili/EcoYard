import 'dart:convert';
import 'dart:io';

import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late SpeciesResolver resolver;

  setUpAll(() => resolver = realResolver());

  group('the case table', () {
    final cases = (jsonDecode(File('test/resolver_cases.json').existsSync()
            ? File('test/resolver_cases.json').readAsStringSync()
            : File('${repoRoot().path}/packages/ecoyard_core/test/resolver_cases.json')
                .readAsStringSync())['cases'] as List)
        .cast<Map<String, dynamic>>();

    for (final c in cases) {
      final label =
          '[${c['origin']}] "${c['raw']}"${c['sci'] != null ? ' / ${c['sci']}' : ''}'
          ' -> ${c['expect']}${c['taxon'] != null ? ' (${c['taxon']})' : ''}';
      test(label, () {
        final m = resolver.resolve(
          rawName: c['raw'] as String,
          scientificName: c['sci'] as String?,
        );
        expect(m.source.name, c['expect'], reason: m.toString());
        expect(m.taxonId, c['taxon'], reason: m.toString());
      });
    }

    test('every row is marked real or synthetic', () {
      expect(cases.map((c) => c['origin']).toSet(), {'real', 'synthetic'});
    });
  });

  group('what a match carries', () {
    test('a resolved match shows our name, not the typo or alias', () {
      final m = resolver.resolve(rawName: 'cardinals');
      expect(m.displayName, 'Northern Cardinal');
      expect(m.scientificName, 'Cardinalis cardinalis');
      expect(m.isResolved, isTrue);
      expect(m.isBird, isTrue);
    });

    test('an unresolved match keeps the provider\'s own words', () {
      final m = resolver.resolve(rawName: 'Laughing Kookaburra');
      expect(m.displayName, 'Laughing Kookaburra');
      expect(m.taxonId, isNull);
      expect(m.isResolved, isFalse);
      expect(m.isBird, isTrue,
          reason: 'a real bird we simply have no content for');
    });

    test('an unresolved BirdNET label keeps its scientific name', () {
      final m =
          resolver.resolve(rawName: 'Poecile carolinensis_Carolina Chickadee');
      expect(m.displayName, 'Carolina Chickadee');
      expect(m.scientificName, 'Poecile carolinensis');
    });

    test('a non-bird is flagged so the UI never says "possible match"', () {
      final m = resolver.resolve(rawName: 'Human vocal', confidence: 0.43);
      expect(m.isBird, isFalse);
      expect(m.isResolved, isFalse);
      expect(m.providerConfidence, 0.43);
    });

    test('a scientific name inside text resolves, but only as an alias', () {
      final m =
          resolver.resolve(rawName: 'a small red bird (Cardinalis cardinalis)');
      expect(m.taxonId, 'norcar');
      expect(m.source, ResolutionSource.alias);
    });

    test('a provider-supplied scientific name is an exact label match', () {
      final m = resolver.resolve(
          rawName: 'Cardinal, probably',
          scientificName: 'Cardinalis cardinalis');
      expect(m.source, ResolutionSource.exactLabel);
    });
  });

  group('confidence combines provider score with how the name matched', () {
    MatchConfidence conf(String raw, {String? sci, double? c}) => resolver
        .resolve(rawName: raw, scientificName: sci, confidence: c)
        .confidence;

    test('exact label: high unless the provider itself is unsure', () {
      const sci = 'Cardinalis cardinalis';
      expect(conf('Northern Cardinal', sci: sci), MatchConfidence.high);
      expect(conf('Northern Cardinal', sci: sci, c: 0.9), MatchConfidence.high);
      expect(
          conf('Northern Cardinal', sci: sci, c: 0.5), MatchConfidence.medium);
      expect(conf('Northern Cardinal', sci: sci, c: 0.2), MatchConfidence.low);
    });

    test('alias with no provider score (NatureLM) is medium, never high', () {
      expect(conf('Northern Cardinal'), MatchConfidence.medium);
    });

    test('alias with a provider score follows it', () {
      expect(conf('Northern Cardinal', c: 0.9), MatchConfidence.high);
      expect(conf('Northern Cardinal', c: 0.5), MatchConfidence.medium);
      expect(conf('Northern Cardinal', c: 0.1), MatchConfidence.low);
    });

    test('a fuzzy match at 0.9 is NOT high', () {
      expect(conf('Northern Cardnial', c: 0.9), MatchConfidence.medium);
      expect(conf('Northern Cardnial', c: 0.5), MatchConfidence.low);
      expect(conf('Northern Cardnial'), MatchConfidence.low);
    });

    test('unresolved and not-a-bird are always low', () {
      expect(conf('Laughing Kookaburra', c: 0.99), MatchConfidence.low);
      expect(conf('Human vocal', c: 0.99), MatchConfidence.low);
    });
  });

  group('refusing to guess', () {
    test('two species equally close to a typo -> unresolved', () {
      // Make a resolver where "blue jay" and "blue jey" owners differ.
      final repo = ReferenceRepository.fromJson(withEdit('aliases', (j) {
        (j['aliases'] as List).add({
          'taxonId': 'amerob',
          'names': ['blue joy'],
        });
      }));
      final r = SpeciesResolver(repo);
      // "blue joay" is one edit from both "blue jay" (blujay) and "blue joy" (amerob).
      expect(
          r.resolve(rawName: 'blue joay').source, ResolutionSource.unresolved);
    });

    test('short strings are never fuzzy-matched', () {
      expect(resolver.resolve(rawName: 'blue jy').source,
          ResolutionSource.unresolved);
      expect(resolver.resolve(rawName: 'robn').source,
          ResolutionSource.unresolved);
    });

    test('a partial name is not enough', () {
      expect(resolver.resolve(rawName: 'carolina').source,
          ResolutionSource.unresolved);
      expect(resolver.resolve(rawName: 'northern').source,
          ResolutionSource.unresolved);
    });
  });

  group('BirdNET label list (optional, set BIRDNET_LABELS to a labels file)',
      () {
    final path = Platform.environment['BIRDNET_LABELS'];

    test(
      'all 6,522 labels end up resolved-to-slice, not-a-bird, or unresolved',
      () {
        final lines = File(path!)
            .readAsLinesSync()
            .where((l) => l.trim().isNotEmpty)
            .toList();
        expect(lines.length, greaterThan(6000));

        final resolved = <String>{};
        var notBird = 0;
        var unresolved = 0;
        for (final line in lines) {
          final m = resolver.resolve(rawName: line);
          if (m.isResolved) {
            resolved.add(m.taxonId!);
            expect(m.source, ResolutionSource.exactLabel, reason: line);
          } else if (!m.isBird) {
            notBird++;
          } else {
            unresolved++;
          }
        }

        expect(resolved, hasLength(10), reason: 'exactly the 10 slice species');
        expect(notBird, 11, reason: 'BirdNET non-bird classes');
        expect(unresolved, lines.length - 10 - 11);
      },
      skip: path == null
          ? 'set BIRDNET_LABELS=/path/to/BirdNET_GLOBAL_6K_V2.4_Labels.txt to run'
          : false,
    );
  });
}
