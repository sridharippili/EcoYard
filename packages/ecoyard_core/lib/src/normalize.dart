/// Name normalization shared by the SpeciesResolver and the content
/// validator. One implementation, so a duplicate alias the validator rejects
/// is exactly a collision the resolver would have hit at runtime.
library;

/// Words that describe the individual or the sound, not the species.
const Set<String> _qualifierWords = {
  'male',
  'female',
  'juvenile',
  'juvenal',
  'immature',
  'adult',
  'chick',
  'fledgling',
  'nestling',
  'song',
  'songs',
  'call',
  'calls',
};

/// Leading chatter a language model may put before the name. Tried in order,
/// longest first, repeatedly, on the normalized text.
const List<String> _fillerPrefixes = [
  'the bird is an',
  'the bird is a',
  'the bird is',
  'this is an',
  'this is a',
  'this is',
  'it sounds like an',
  'it sounds like a',
  'it sounds like',
  'it is an',
  'it is a',
  'it is',
  'i hear an',
  'i hear a',
  'i hear',
  'probably',
  'likely',
  'possibly',
  'maybe',
  'an',
  'a',
  'the',
];

const Map<String, String> _irregularPlurals = {
  'titmice': 'titmouse',
  'geese': 'goose',
  'mice': 'mouse',
};

final RegExp _nonWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
final RegExp _apostrophes = RegExp("['’ʼ]");
final RegExp _parenthetical = RegExp(r'\(([^)]*)\)');
final RegExp _binomial = RegExp(r'^[A-Z][a-z]+ [a-z]+(?: [a-z]+)?$');

/// Lowercases and turns every run of punctuation into one space.
/// Apostrophes vanish ("Cooper's" -> "coopers"), hyphens become spaces
/// ("Black-capped" -> "black capped").
String normalizeName(String raw) {
  final lower = raw.toLowerCase().replaceAll(_apostrophes, '');
  return lower.replaceAll(_nonWord, ' ').trim();
}

/// A free-text species answer, cleaned up.
class ParsedName {
  const ParsedName({required this.name, this.scientificHint});

  /// Normalized common name with qualifiers and filler removed.
  final String name;

  /// A scientific name found in parentheses, e.g. from
  /// "Northern Cardinal (Cardinalis cardinalis)". Original capitalization.
  final String? scientificHint;
}

/// Cleans a model's free-text answer: drops `(male)`-style qualifiers, keeps
/// a parenthesized scientific name as a hint, strips filler like "The bird is
/// a", qualifier words, and extra spaces.
ParsedName parseFreeText(String raw) {
  String? hint;
  final withoutParens = raw.replaceAllMapped(_parenthetical, (m) {
    final inner = (m.group(1) ?? '').trim();
    if (_binomial.hasMatch(inner)) hint ??= inner;
    return ' ';
  });

  var text = normalizeName(withoutParens);

  // Strip filler prefixes until none applies.
  var changed = true;
  while (changed) {
    changed = false;
    for (final p in _fillerPrefixes) {
      if (text == p) {
        text = '';
        changed = true;
        break;
      }
      if (text.startsWith('$p ')) {
        text = text.substring(p.length + 1).trimLeft();
        changed = true;
        break;
      }
    }
  }

  final tokens = text
      .split(' ')
      .where((t) => t.isNotEmpty && !_qualifierWords.contains(t))
      .toList();
  return ParsedName(name: tokens.join(' '), scientificHint: hint);
}

/// The name itself, plus a version with the last word singularized, because
/// models say "cardinals" and "blue jays". Distinct, in order.
List<String> nameVariants(String normalized) {
  if (normalized.isEmpty) return const [];
  final out = <String>[normalized];
  final singular = _singularizeLast(normalized);
  if (singular != normalized) out.add(singular);
  return out;
}

String _singularizeLast(String s) {
  final i = s.lastIndexOf(' ');
  final head = i < 0 ? '' : s.substring(0, i + 1);
  final last = i < 0 ? s : s.substring(i + 1);

  final irregular = _irregularPlurals[last];
  if (irregular != null) return head + irregular;

  String? singular;
  if (last.length > 3 && last.endsWith('ches')) {
    singular = last.substring(0, last.length - 2);
  } else if (last.length > 3 && last.endsWith('shes')) {
    singular = last.substring(0, last.length - 2);
  } else if (last.length > 3 && last.endsWith('sses')) {
    singular = last.substring(0, last.length - 2);
  } else if (last.length > 3 &&
      last.endsWith('s') &&
      !last.endsWith('ss') &&
      !last.endsWith('us') &&
      !last.endsWith('is')) {
    singular = last.substring(0, last.length - 1);
  }
  return singular == null ? s : head + singular;
}

/// Edit distance between [a] and [b], or `maxDistance + 1` as soon as it is
/// certain to exceed [maxDistance].
int levenshtein(String a, String b, {int maxDistance = 1 << 20}) {
  if (a == b) return 0;
  if ((a.length - b.length).abs() > maxDistance) return maxDistance + 1;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    var rowMin = cur[0];
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var v = prev[j - 1] + cost;
      if (prev[j] + 1 < v) v = prev[j] + 1;
      if (cur[j - 1] + 1 < v) v = cur[j - 1] + 1;
      cur[j] = v;
      if (v < rowMin) rowMin = v;
    }
    if (rowMin > maxDistance) return maxDistance + 1;
    prev = cur;
  }
  return prev[b.length];
}
