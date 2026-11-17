import 'dart:convert';
import 'dart:io';

import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:test/test.dart';

import 'support.dart';

Map<String, dynamic> base() => {
      'schemaVersion': 1,
      'reviewStatus': 'reviewed',
      'modelVersion': 'm1',
      'sampleRate': 48000,
      'minTailSeconds': 1.0,
      'topN': 5,
      'scoreFloor': 0.25,
      'licenceCleared': true,
      'files': [
        {
          'role': 'model',
          'name': 'm1.tflite',
          'url': 'https://example.org/m1.tflite',
          'bytes': 10,
          'sha256': 'a' * 64,
        },
        {
          'role': 'labels',
          'name': 'm1-labels.txt',
          'url': 'https://example.org/m1-labels.txt',
          'bytes': 5,
          'sha256': 'b' * 64,
        },
      ],
    };

List<dynamic> files(Map<String, dynamic> m) => m['files'] as List;

List<String> errs(Map<String, dynamic> m, {bool strict = false}) =>
    validateOfflineModel(jsonEncode(m), strict: strict)
        .where((i) => i.severity == IssueSeverity.error)
        .map((i) => i.message)
        .toList();

void main() {
  group('OfflineModelConfig.parse', () {
    test('reads a good file', () {
      final c = OfflineModelConfig.parse(jsonEncode(base()));
      expect(c.modelVersion, 'm1');
      expect(c.isDownloadable, isTrue);
      expect(c.totalBytes, 15);
      expect(c.fileFor('labels')!.name, 'm1-labels.txt');
    });
    test('junk gives "none", never throws', () {
      for (final t in ['', 'x', '[]', '{}', '{"files": 3}']) {
        final c = OfflineModelConfig.parse(t);
        expect(c.files, isEmpty, reason: t);
        expect(c.isDownloadable, isFalse);
      }
    });
    test('a wrongly typed file entry turns the whole thing off', () {
      final m = base();
      files(m)[0]['bytes'] = '10';
      expect(OfflineModelConfig.parse(jsonEncode(m)).files, isEmpty);
    });
    test('an empty address means not downloadable', () {
      final m = base();
      files(m)[1]['url'] = '';
      expect(OfflineModelConfig.parse(jsonEncode(m)).isDownloadable, isFalse);
    });
    test('an http address means not downloadable', () {
      final m = base();
      files(m)[0]['url'] = 'http://example.org/x';
      expect(OfflineModelConfig.parse(jsonEncode(m)).isDownloadable, isFalse);
    });
    test('a missing labels file means not downloadable', () {
      final m = base();
      files(m).removeAt(1);
      expect(OfflineModelConfig.parse(jsonEncode(m)).isDownloadable, isFalse);
    });
  });

  group('validateOfflineModel', () {
    test('a finished file is clean, even strict', () {
      expect(errs(base(), strict: true), isEmpty);
      expect(validateOfflineModel(jsonEncode(base()), strict: true), isEmpty);
    });
    test('real mistakes are errors in normal mode', () {
      var m = base();
      files(m)[0]['url'] = 'http://x/y';
      expect(errs(m), contains('m1.tflite: the address must be https'));
      m = base();
      files(m)[0]['sha256'] = 'XYZ';
      expect(errs(m).single, contains('sha256'));
      m = base();
      files(m)[0]['bytes'] = 0;
      expect(errs(m).single, contains('bytes'));
      m = base();
      files(m)[1]['name'] = 'm1.tflite';
      expect(errs(m).any((e) => e.contains('duplicate')), isTrue);
      m = base();
      files(m)[0]['name'] = 'other.tflite';
      expect(errs(m).single, contains('modelVersion'));
      m = base()..['scoreFloor'] = 1.5;
      expect(errs(m).single, contains('scoreFloor'));
      m = base()..['topN'] = 0;
      expect(errs(m).single, contains('topN'));
      m = base()..['schemaVersion'] = 2;
      expect(errs(m).single, contains('schemaVersion'));
      m = base();
      files(m).removeAt(0);
      expect(errs(m).single, contains('"model"'));
    });
    test('not valid JSON or not an object is an error', () {
      expect(validateOfflineModel('nope'), isNotEmpty);
      expect(validateOfflineModel('[]'), isNotEmpty);
    });
    test('unfinished work warns now and fails with strict', () {
      final m = base()
        ..['reviewStatus'] = 'draft'
        ..['scoreFloorProvisional'] = true
        ..['licenceCleared'] = false;
      files(m)[0]['url'] = '';
      expect(errs(m), isEmpty);
      final warnings = validateOfflineModel(jsonEncode(m))
          .where((i) => i.severity == IssueSeverity.warning)
          .toList();
      expect(warnings, hasLength(4));
      expect(errs(m, strict: true), hasLength(4));
    });
  });

  group('the real content/offline_model.json', () {
    final text = File(
      '${repoRoot().path}/content/offline_model.json',
    ).readAsStringSync();
    test('has no errors in normal mode', () {
      expect(
        validateOfflineModel(
          text,
        ).where((i) => i.severity == IssueSeverity.error),
        isEmpty,
      );
    });
    test('matches the two files in the spike, byte for byte', () {
      final c = OfflineModelConfig.parse(text);
      expect(c.fileFor('model')!.bytes, 51726412);
      expect(c.fileFor('labels')!.bytes, 259740);
    });
    test(
        'is not releasable until address, review, floor and licence are '
        'settled', () {
      expect(
        validateOfflineModel(
          text,
          strict: true,
        ).where((i) => i.severity == IssueSeverity.error),
        isNotEmpty,
      );
    });
  });
}
