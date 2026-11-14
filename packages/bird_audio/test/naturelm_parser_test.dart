import 'package:bird_audio/bird_audio.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> names(String raw) =>
    parseNatureLmResult(raw).map((d) => d.speciesText).toList();

void main() {
  group('parseNatureLmResult', () {
    test('strips the timestamp prefix and trailing newline', () {
      expect(names('#0.00s - 10.00s#: Laughing Kookaburra\n'),
          ['Laughing Kookaburra']);
    });

    test('keeps windows separate instead of gluing them together', () {
      expect(
        names('#0.00s - 3.00s#: Northern Cardinal\n'
            '#3.00s - 6.00s#: Blue Jay\n'),
        ['Northern Cardinal', 'Blue Jay'],
      );
    });

    test('drops repeats across windows, case-insensitively, first-seen order',
        () {
      expect(
        names('#0.00s - 3.00s#: Northern Cardinal\n'
            '#3.00s - 6.00s#: northern cardinal\n'
            '#6.00s - 9.00s#: Blue Jay\n'),
        ['Northern Cardinal', 'Blue Jay'],
      );
    });

    test('handles Windows line endings', () {
      expect(
          names(
              '#0.00s - 3.00s#: Blue Jay\r\n#3.00s - 6.00s#: Carolina Wren\r\n'),
          ['Blue Jay', 'Carolina Wren']);
    });

    test('falls back to splitting on ": " when there is no timestamp', () {
      expect(names('Answer: American Robin'), ['American Robin']);
    });

    test('a bare name passes through unchanged', () {
      expect(names('American Robin'), ['American Robin']);
    });

    test('leaves qualifiers for the SpeciesResolver to normalize', () {
      expect(names('#0.00s - 10.00s#: Cardinal (male)\n'), ['Cardinal (male)']);
    });

    test('empty and whitespace-only input yields no detections', () {
      expect(parseNatureLmResult(''), isEmpty);
      expect(parseNatureLmResult('  \n \r\n'), isEmpty);
    });

    test('a timestamp with no species yields no detections', () {
      expect(parseNatureLmResult('#0.00s - 10.00s#: \n'), isEmpty);
    });

    test('NatureLM gives no scientific name and no confidence', () {
      final d = parseNatureLmResult('#0.00s - 10.00s#: Blue Jay\n').single;
      expect(d.scientificName, isNull);
      expect(d.confidence, isNull);
    });
  });
}
