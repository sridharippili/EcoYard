import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:test/test.dart';

import 'support.dart';

List<String> errorsOf(ValidationReport r) =>
    r.errors.map((e) => e.toString()).toList();

Map<String, dynamic> action(Map<String, dynamic> json, String id) =>
    (json['actions'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((a) => a['id'] == id);

void main() {
  group('action fields the engine depends on', () {
    test('priority outside 1-3 is an error', () {
      final report = validateContent(withEdit('actions', (j) {
        action(j, 'add-water-source')['priority'] = 4;
      }));
      expect(errorsOf(report), contains(contains('priority must be 1-3')));
    });

    test('a missing priority is refused by the parser', () {
      final report = validateContent(withEdit('actions', (j) {
        action(j, 'add-water-source').remove('priority');
      }));
      expect(errorsOf(report), contains(contains('"priority"')));
    });

    test('forBirdIds naming an unknown bird is an error', () {
      final report = validateContent(withEdit('actions', (j) {
        action(j, 'add-nest-box')['forBirdIds'] = ['bkcchi', 'ghost'];
      }));
      expect(errorsOf(report), contains(contains('unknown bird "ghost"')));
    });

    test('forBirdIds listing a bird twice is an error', () {
      final report = validateContent(withEdit('actions', (j) {
        action(j, 'add-nest-box')['forBirdIds'] = ['bkcchi', 'bkcchi'];
      }));
      expect(errorsOf(report), contains(contains('lists a bird twice')));
    });

    test('an action without forBirdIds applies to every bird', () {
      final repo = ReferenceRepository.fromJson(realContent());
      expect(repo.actionById('add-water-source')!.forBirdIds, isEmpty);
      expect(repo.actionById('add-nest-box')!.forBirdIds,
          ['bkcchi', 'tuftit', 'carwre']);
    });
  });

  group('birds in the real content', () {
    test('every bird has the safety need (window collisions)', () {
      final repo = ReferenceRepository.fromJson(realContent());
      for (final b in repo.birds) {
        expect(b.supportNeeds.map((n) => n.need), contains(Need.safety),
            reason: b.id);
      }
    });

    test('the hummingbird has no water need; every other bird does', () {
      final repo = ReferenceRepository.fromJson(realContent());
      for (final b in repo.birds) {
        final hasWater = b.supportNeeds.any((n) => n.need == Need.water);
        expect(hasWater, b.id != 'rthhum', reason: b.id);
      }
    });
  });
}
