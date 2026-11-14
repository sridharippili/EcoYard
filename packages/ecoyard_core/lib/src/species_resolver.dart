/// Turns whatever a provider said into a stable taxon id, or says plainly
/// that it could not. Never fakes a match.
library;

import 'models.dart';
import 'normalize.dart';
import 'reference_repository.dart';

/// How a name was matched, strongest first.
enum ResolutionSource {
  /// A scientific name given by the provider matched exactly.
  exactLabel,

  /// A known name or alias matched exactly (after cleanup).
  alias,

  /// A near-miss spelling matched one species and no other.
  fuzzy,

  /// BirdNET's non-bird classes, or a "no bird" answer.
  notABird,

  /// Not in our content. The raw name is kept so the UI can show it.
  unresolved,
}

/// How much to trust a match. Combines provider confidence with how the name
/// was matched, so a fuzzy match at 0.9 is never "high".
enum MatchConfidence { high, medium, low }

class SpeciesMatch {
  const SpeciesMatch({
    required this.displayName,
    required this.source,
    this.taxonId,
    this.commonName,
    this.scientificName,
    this.providerConfidence,
  });

  /// What to show: the resolved common name, or the provider's own words.
  final String displayName;
  final ResolutionSource source;

  /// Set only when the species is in our content.
  final String? taxonId;
  final String? commonName;
  final String? scientificName;

  /// The provider's own 0..1 score. Null for NatureLM, which gives none.
  final double? providerConfidence;

  /// True when we know this species and have habitat content for it.
  bool get isResolved => taxonId != null;

  /// False for "Human vocal", "Gun", "unknown" and similar.
  bool get isBird => source != ResolutionSource.notABird;

  MatchConfidence get confidence {
    final c = providerConfidence;
    switch (source) {
      case ResolutionSource.notABird:
      case ResolutionSource.unresolved:
        return MatchConfidence.low;
      case ResolutionSource.exactLabel:
        if (c == null || c >= 0.7) return MatchConfidence.high;
        return c >= 0.4 ? MatchConfidence.medium : MatchConfidence.low;
      case ResolutionSource.alias:
        if (c == null) return MatchConfidence.medium;
        if (c >= 0.7) return MatchConfidence.high;
        return c >= 0.4 ? MatchConfidence.medium : MatchConfidence.low;
      case ResolutionSource.fuzzy:
        // A guessed spelling is never better than medium.
        return (c != null && c >= 0.7)
            ? MatchConfidence.medium
            : MatchConfidence.low;
    }
  }

  @override
  String toString() =>
      'SpeciesMatch($displayName, ${source.name}, taxon: $taxonId)';
}

abstract interface class SpeciesResolving {
  SpeciesMatch resolve({
    required String rawName,
    String? scientificName,
    double? confidence,
  });
}

class SpeciesResolver implements SpeciesResolving {
  SpeciesResolver(ReferenceRepository repo)
      : _birds = {for (final b in repo.birds) b.id: b} {
    for (final b in repo.birds) {
      _addName(b.commonName, b.id);
      _addName(b.scientificName, b.id);
      _byScientific[normalizeName(b.scientificName)] = b.id;
    }
    for (final e in repo.aliases.aliases.entries) {
      for (final n in e.value) {
        _addName(n, e.key);
      }
    }
    _notABird = repo.aliases.notABird.map(normalizeName).toSet();
    _noSpecies = repo.aliases.noSpeciesPhrases.map(normalizeName).toSet();
  }

  final Map<String, Bird> _birds;
  final Map<String, String> _byName = {}; // normalized name -> taxonId
  final Map<String, String> _byScientific = {}; // normalized sci name -> id
  late final Set<String> _notABird;
  late final Set<String> _noSpecies;

  void _addName(String name, String taxonId) {
    final key = normalizeName(name);
    if (key.isNotEmpty) _byName.putIfAbsent(key, () => taxonId);
  }

  @override
  SpeciesMatch resolve({
    required String rawName,
    String? scientificName,
    double? confidence,
  }) {
    var common = rawName.trim();
    var sci = (scientificName ?? '').trim();
    var structuredSci = sci.isNotEmpty;

    // BirdNET's raw label: "Scientific_Common".
    final us = common.indexOf('_');
    if (us > 0) {
      if (sci.isEmpty) {
        sci = common.substring(0, us).trim();
        structuredSci = true;
      }
      common = common.substring(us + 1).trim();
    }

    final parsed = parseFreeText(common);
    final nameKey = parsed.name;
    final sciKey = normalizeName(sci);

    // Not a bird at all.
    if (_notABird.contains(nameKey) ||
        _notABird.contains(sciKey) ||
        _noSpecies.contains(nameKey)) {
      return SpeciesMatch(
        displayName: common.isEmpty ? sci : common,
        source: ResolutionSource.notABird,
        providerConfidence: confidence,
      );
    }

    // Scientific name: exact when the provider gave it, alias when we only
    // found it in parentheses inside free text.
    final hint = sci.isNotEmpty ? sci : parsed.scientificHint;
    if (hint != null) {
      final id = _byScientific[normalizeName(hint)];
      if (id != null) {
        return _resolved(
          id,
          structuredSci ? ResolutionSource.exactLabel : ResolutionSource.alias,
          confidence,
        );
      }
    }

    // Known names, with a plural fallback.
    for (final v in nameVariants(nameKey)) {
      final id = _byName[v];
      if (id != null) return _resolved(id, ResolutionSource.alias, confidence);
    }

    // Near-miss spelling, only when it can only mean one species.
    final fuzzyId = _fuzzy(nameKey);
    if (fuzzyId != null) {
      return _resolved(fuzzyId, ResolutionSource.fuzzy, confidence);
    }

    return SpeciesMatch(
      displayName: common.isEmpty ? sci : common,
      scientificName: sci.isEmpty ? parsed.scientificHint : sci,
      source: ResolutionSource.unresolved,
      providerConfidence: confidence,
    );
  }

  SpeciesMatch _resolved(String id, ResolutionSource source, double? conf) {
    final b = _birds[id]!;
    return SpeciesMatch(
      displayName: b.commonName,
      commonName: b.commonName,
      scientificName: b.scientificName,
      taxonId: id,
      source: source,
      providerConfidence: conf,
    );
  }

  /// Allowed edits scale with length: short names are too easy to confuse.
  static int _allowedDistance(int length) {
    if (length < 8) return 0;
    if (length < 12) return 1;
    return 2;
  }

  String? _fuzzy(String query) {
    final tokens = query.split(' ').length;
    final candidates = <String>{query, ...nameVariants(query)};

    int? bestDistance;
    final bestTaxa = <String>{};

    for (final q in candidates) {
      final allowed = _allowedDistance(q.length);
      if (allowed == 0) continue;
      for (final e in _byName.entries) {
        // Same number of words, so "house wren" never matches part of a name.
        if (e.key.split(' ').length != tokens) continue;
        final d = levenshtein(q, e.key, maxDistance: allowed);
        if (d > allowed) continue;
        if (bestDistance == null || d < bestDistance) {
          bestDistance = d;
          bestTaxa
            ..clear()
            ..add(e.value);
        } else if (d == bestDistance) {
          bestTaxa.add(e.value);
        }
      }
    }
    return bestTaxa.length == 1 ? bestTaxa.first : null;
  }
}
