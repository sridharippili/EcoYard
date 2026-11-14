import 'package:ecoyard_core/src/normalize.dart';
import 'package:test/test.dart';

void main() {
  group('normalizeName', () {
    test('lowercases and turns punctuation into single spaces', () {
      expect(
          normalizeName('Black-capped  Chickadee!'), 'black capped chickadee');
    });

    test('apostrophes vanish instead of splitting the word', () {
      expect(normalizeName("Steller's Jay"), 'stellers jay');
      expect(normalizeName('Cooper’s Hawk'), 'coopers hawk');
    });

    test('empty and symbol-only input normalize to empty', () {
      expect(normalizeName(''), '');
      expect(normalizeName('  #\$%  '), '');
    });
  });

  group('parseFreeText', () {
    String name(String s) => parseFreeText(s).name;

    test('drops (male)/(female)/(juvenile) qualifiers', () {
      expect(name('Cardinal (male)'), 'cardinal');
      expect(name('Northern Cardinal (Female)'), 'northern cardinal');
      expect(name('Downy Woodpecker juvenile'), 'downy woodpecker');
    });

    test('drops song/call words', () {
      expect(name('Black-capped Chickadee song'), 'black capped chickadee');
      expect(name('Blue Jay calls'), 'blue jay');
    });

    test('keeps a parenthesized scientific name as a hint', () {
      final p = parseFreeText('Northern Cardinal (Cardinalis cardinalis)');
      expect(p.name, 'northern cardinal');
      expect(p.scientificHint, 'Cardinalis cardinalis');
    });

    test('ignores a parenthetical that is not a scientific name', () {
      expect(parseFreeText('Blue Jay (probably)').scientificHint, isNull);
    });

    test('strips filler before the name, even stacked', () {
      expect(name('The bird is a Northern Cardinal.'), 'northern cardinal');
      expect(name('It sounds like a Blue Jay'), 'blue jay');
      expect(name('Probably an American Robin'), 'american robin');
      expect(name('likely the Carolina Wren'), 'carolina wren');
    });

    test('does not eat a name that merely starts with a filler letter', () {
      expect(name('American Robin'), 'american robin');
      expect(name('Acadian Flycatcher'), 'acadian flycatcher');
    });

    test('empty, filler-only and qualifier-only input become empty', () {
      expect(name(''), '');
      expect(name('the bird is'), '');
      expect(name('(male)'), '');
    });
  });

  group('nameVariants', () {
    test('adds a singular form of the last word', () {
      expect(nameVariants('blue jays'), ['blue jays', 'blue jay']);
      expect(nameVariants('cardinals'), ['cardinals', 'cardinal']);
      expect(nameVariants('american goldfinches'),
          ['american goldfinches', 'american goldfinch']);
    });

    test('handles irregular plurals', () {
      expect(nameVariants('tufted titmice'),
          ['tufted titmice', 'tufted titmouse']);
    });

    test('leaves words that only look plural alone', () {
      expect(nameVariants('harris sparrow'), ['harris sparrow']);
      expect(nameVariants('northern mockingbird'), ['northern mockingbird']);
      expect(nameVariants('canvasback'), ['canvasback']);
    });

    test('empty gives nothing', () => expect(nameVariants(''), isEmpty));
  });

  group('levenshtein', () {
    test('basic distances', () {
      expect(levenshtein('cardinal', 'cardinal'), 0);
      expect(levenshtein('cardinal', 'cardinol'), 1);
      expect(levenshtein('kitten', 'sitting'), 3);
      expect(levenshtein('', 'abc'), 3);
    });

    test('gives up early once past the limit', () {
      expect(
          levenshtein('northern cardinal', 'desert cardinal', maxDistance: 2),
          3);
      expect(levenshtein('a', 'abcdef', maxDistance: 2), 3);
    });
  });
}
