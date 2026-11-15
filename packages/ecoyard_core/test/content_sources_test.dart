import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('sources', () {
    test('every content file lists where it came from', () {
      final repo = ReferenceRepository.fromJson(realContent());
      for (final m in repo.meta.values) {
        expect(m.sources, isNotEmpty, reason: m.file);
      }
    });

    test('allSources has no repeats and keeps first-seen order', () {
      final repo = ReferenceRepository.fromJson(realContent());
      final all = repo.allSources;
      expect(all.toSet().length, all.length);
      expect(all.first, repo.meta['birds.json']!.sources.first);
    });

    test('a missing or malformed sources list is empty, never an error', () {
      final repo = ReferenceRepository.fromJson(
        withEdit('tips', (j) {
          j['sources'] = ['ok', 3, '', null, '  ', 'also ok'];
        }),
      );
      expect(repo.meta['tips.json']!.sources, ['ok', 'also ok']);
      final repo2 = ReferenceRepository.fromJson(
        withEdit('tips', (j) => j.remove('sources')),
      );
      expect(repo2.meta['tips.json']!.sources, isEmpty);
    });
  });
}
