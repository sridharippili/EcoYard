import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('bundled content', () {
    test(
      'app/assets/content equals content/ (run scripts/sync_content.sh)',
      () {
        final source = Directory('../content')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.json'))
            .toList();
        expect(source, isNotEmpty);
        for (final f in source) {
          final name = f.uri.pathSegments.last;
          final copy = File('assets/content/$name');
          expect(copy.existsSync(), isTrue, reason: '$name missing in assets');
          expect(
            copy.readAsStringSync(),
            f.readAsStringSync(),
            reason: '$name differs: run scripts/sync_content.sh',
          );
        }
      },
    );
  });
}
