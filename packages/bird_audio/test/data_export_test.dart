import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:bird_audio/bird_audio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('ecoyard_export_'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  List<File> exports() => dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.contains('ecoyard-my-data-'))
      .toList();

  const data = '{"app":"EcoYard","plan":[{"title":"Add a water source"}]}';

  ShareSheetExporter make(
    Future<ShareResult> Function(ShareParams) share,
  ) =>
      ShareSheetExporter(tempDir: () async => dir, share: share);

  group('while the share sheet is open', () {
    test('the file exists and holds exactly the data, as JSON', () async {
      String? seen;
      String? name;
      String? mime;
      await make((p) async {
        final f = File(p.files!.single.path);
        seen = await f.readAsString();
        name = f.uri.pathSegments.last;
        mime = p.files!.single.mimeType;
        return const ShareResult('ok', ShareResultStatus.success);
      }).export(data);
      expect(seen, data);
      expect(jsonDecode(seen!), isA<Map>());
      expect(name, matches(RegExp(r'^ecoyard-my-data-\d+\.json$')));
      expect(mime, 'application/json');
    });

    test('it is shared with a subject and the position it was given', () async {
      ShareParams? got;
      const origin = Rect.fromLTWH(10, 20, 30, 40);
      await make((p) async {
        got = p;
        return const ShareResult('ok', ShareResultStatus.success);
      }).export(data, origin: origin);
      expect(got!.subject, 'My EcoYard data');
      expect(got!.sharePositionOrigin, origin);
    });
  });

  group('afterwards the file is always gone', () {
    test('after a successful share', () async {
      final r = await make(
        (_) async => const ShareResult('ok', ShareResultStatus.success),
      ).export(data);
      expect(r, ExportOutcome.shared);
      expect(exports(), isEmpty);
    });

    test('after the user dismisses the sheet', () async {
      final r = await make(
        (_) async => const ShareResult('', ShareResultStatus.dismissed),
      ).export(data);
      expect(r, ExportOutcome.dismissed);
      expect(exports(), isEmpty);
    });

    test(
        'when the share sheet throws: reported as failed, never thrown, '
        'file still removed', () async {
      final r = await make((_) async => throw StateError('no sheet')).export(
        data,
      );
      expect(r, ExportOutcome.failed);
      expect(exports(), isEmpty);
    });

    test(
        'when the share sheet reports it is unavailable it is still '
        'treated as done, with the file removed', () async {
      final r = await make(
        (_) async => const ShareResult('', ShareResultStatus.unavailable),
      ).export(data);
      expect(r, isIn([ExportOutcome.shared, ExportOutcome.dismissed]));
      expect(exports(), isEmpty);
    });
  });

  group('failures', () {
    test('a folder that cannot be written is "failed", not a crash', () async {
      var shared = false;
      final r = await ShareSheetExporter(
        tempDir: () async => Directory('${dir.path}/does/not/exist'),
        share: (_) async {
          shared = true;
          return const ShareResult('ok', ShareResultStatus.success);
        },
      ).export(data);
      expect(r, ExportOutcome.failed);
      expect(shared, isFalse,
          reason: 'nothing to share if nothing was written');
    });

    test('a temp folder that errors is "failed", not a crash', () async {
      final r = await ShareSheetExporter(
        tempDir: () async => throw StateError('no temp'),
        share: (_) async => const ShareResult('ok', ShareResultStatus.success),
      ).export(data);
      expect(r, ExportOutcome.failed);
    });

    test('unicode, quotes and a large plan survive the round trip', () async {
      final big = jsonEncode({
        'title': 'He said "hi" \u{1F426}\n',
        'rows': List.generate(5000, (i) => 'row $i'),
      });
      String? seen;
      await make((p) async {
        seen = await File(p.files!.single.path).readAsString();
        return const ShareResult('ok', ShareResultStatus.success);
      }).export(big);
      expect(seen, big);
    });
  });

  group('sweep', () {
    ShareSheetExporter plain() => make(
          (_) async => const ShareResult('ok', ShareResultStatus.success),
        );

    test('removes leftover export files and nothing else', () async {
      File('${dir.path}/ecoyard-my-data-123.json').writeAsStringSync('x');
      File('${dir.path}/ecoyard-my-data-9.json').writeAsStringSync('x');
      final keep = [
        File('${dir.path}/other.json')..writeAsStringSync('x'),
        File('${dir.path}/ecoyard-my-data-abc.json')..writeAsStringSync('x'),
        File('${dir.path}/ecoyard_123.m4a')..writeAsStringSync('x'),
        File('${dir.path}/ecoyard-my-data-1.json.bak')..writeAsStringSync('x'),
      ];
      expect(await plain().sweep(), 2);
      expect(
          File('${dir.path}/ecoyard-my-data-123.json').existsSync(), isFalse);
      expect(File('${dir.path}/ecoyard-my-data-9.json').existsSync(), isFalse);
      for (final f in keep) {
        expect(f.existsSync(), isTrue, reason: f.path);
      }
    });

    test('does not touch a folder named like an export', () async {
      final d = Directory('${dir.path}/ecoyard-my-data-5.json')..createSync();
      expect(await plain().sweep(), 0);
      expect(d.existsSync(), isTrue);
    });

    test('an empty or missing folder is 0, never an error', () async {
      expect(await plain().sweep(), 0);
      dir.deleteSync(recursive: true);
      expect(await plain().sweep(), 0);
    });

    test('a failing temp folder is 0, never an error', () async {
      final s = ShareSheetExporter(
        tempDir: () async => throw StateError('no temp'),
        share: (_) async => const ShareResult('ok', ShareResultStatus.success),
      );
      expect(await s.sweep(), 0);
    });
  });
}
