import 'identification.dart';

final RegExp _timestampPrefix = RegExp(r'^#[^#]*#:\s*');

/// Parses the router's `result` text into detections.
///
/// NatureLM answers free text such as `#0.00s - 10.00s#: Laughing Kookaburra\n`,
/// and one line per time window for longer clips. There is no scientific name
/// and no taxon id. Phase 2's SpeciesResolver turns these strings into taxa.
///
/// GardenEar removed every newline before parsing, which glued several
/// windows into one bogus name. This keeps each line separate and drops
/// repeats, preserving first-seen order.
List<Detection> parseNatureLmResult(String raw) {
  final seen = <String>{};
  final out = <Detection>[];

  for (final line in raw.split(RegExp(r'[\r\n]+'))) {
    var text = line.trim();
    if (text.isEmpty) continue;

    if (_timestampPrefix.hasMatch(text)) {
      text = text.replaceFirst(_timestampPrefix, '').trim();
    } else {
      final colon = text.indexOf(': ');
      if (colon >= 0) text = text.substring(colon + 2).trim();
    }

    if (text.isEmpty) continue;
    if (seen.add(text.toLowerCase())) {
      out.add(Detection(speciesText: text));
    }
  }
  return out;
}
