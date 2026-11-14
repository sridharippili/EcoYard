/// Checks the bundled content for the mistakes hand-written JSON drifts into.
/// Pure logic over [ContentFiles]; `scripts/validate_content.dart` supplies
/// the file text and prints the report.
library;

import 'models.dart';
import 'normalize.dart';
import 'reference_repository.dart';

enum IssueSeverity { error, warning }

class ContentIssue {
  const ContentIssue(this.severity, this.file, this.message);

  final IssueSeverity severity;
  final String file;
  final String message;

  @override
  String toString() => '${severity.name.toUpperCase()} $file: $message';
}

class ValidationReport {
  const ValidationReport(this.issues);

  final List<ContentIssue> issues;

  List<ContentIssue> get errors =>
      issues.where((i) => i.severity == IssueSeverity.error).toList();
  List<ContentIssue> get warnings =>
      issues.where((i) => i.severity == IssueSeverity.warning).toList();

  bool get ok => errors.isEmpty;
}

final RegExp _taxonId = RegExp(r'^[a-z0-9]{4,8}$');
final RegExp _binomial = RegExp(r'^[A-Z][a-z]+ [a-z]+$');

/// Validates [files].
///
/// In normal mode, unfinished-but-expected things (draft review status,
/// pending photos) are warnings. With [strict] (run before a release) they
/// are errors.
ValidationReport validateContent(ContentFiles files, {bool strict = false}) {
  final issues = <ContentIssue>[];

  void error(String file, String msg) =>
      issues.add(ContentIssue(IssueSeverity.error, file, msg));
  void warning(String file, String msg) =>
      issues.add(ContentIssue(IssueSeverity.warning, file, msg));
  // Unfinished work: a warning now, an error at release time.
  void gate(String file, String msg) =>
      strict ? error(file, msg) : warning(file, msg);

  final ReferenceRepository repo;
  try {
    repo = ReferenceRepository.fromJson(files);
  } on ContentFormatException catch (e) {
    error(e.file, e.message);
    return ValidationReport(issues);
  }

  // --- file headers -------------------------------------------------------
  final regions = repo.meta.values.map((m) => m.region).toSet();
  if (regions.length > 1) {
    error('(all)', 'files disagree on region: ${regions.join(', ')}');
  }
  final isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  for (final m in repo.meta.values) {
    if (m.reviewStatus == ReviewStatus.draft) {
      gate(m.file,
          'reviewStatus is "draft"; a person must review it before release');
    } else {
      // "reviewed" must say by whom and when, so the flag cannot be flipped
      // without leaving a name.
      if (m.reviewedBy == null) {
        error(m.file, 'reviewStatus is "reviewed" but reviewedBy is missing');
      }
      if (m.reviewedOn == null || !isoDate.hasMatch(m.reviewedOn!)) {
        error(m.file,
            'reviewStatus is "reviewed" but reviewedOn is not a YYYY-MM-DD date');
      }
    }
  }

  // --- duplicate ids ------------------------------------------------------
  void duplicates(String file, Iterable<String> ids, String what) {
    final seen = <String>{};
    for (final id in ids) {
      if (!seen.add(id)) error(file, 'duplicate $what id "$id"');
    }
  }

  duplicates('birds.json', repo.birds.map((b) => b.id), 'bird');
  duplicates('plants.json', repo.plants.map((p) => p.id), 'plant');
  duplicates('actions.json', repo.actions.map((a) => a.id), 'action');
  duplicates('tips.json', repo.tips.map((t) => t.id), 'tip');

  // --- birds --------------------------------------------------------------
  for (final b in repo.birds) {
    if (!_taxonId.hasMatch(b.id)) {
      error('birds.json',
          '${b.id}: id must be an eBird-style code (4-8 lowercase letters/digits)');
    }
    if (!_binomial.hasMatch(b.scientificName)) {
      error('birds.json',
          '${b.id}: scientificName "${b.scientificName}" is not "Genus species"');
    }
    if (b.supportNeeds.isEmpty) {
      error('birds.json', '${b.id}: has no supportNeeds');
    }
  }

  // --- plants -------------------------------------------------------------
  for (final p in repo.plants) {
    final f = 'plants.json';
    if (p.bloomStartMonth < 1 ||
        p.bloomEndMonth > 12 ||
        p.bloomStartMonth > p.bloomEndMonth) {
      error(f, '${p.id}: bloom months must be 1-12 with start <= end');
    }
    if (p.heightFtMin <= 0 || p.heightFtMin > p.heightFtMax) {
      error(f, '${p.id}: heightFt must be positive with min <= max');
    }
    if (p.sun.isEmpty) error(f, '${p.id}: sun must not be empty');
    if (p.spaces.isEmpty) error(f, '${p.id}: spaces must not be empty');
    if (p.benefits.isEmpty) error(f, '${p.id}: benefits must not be empty');

    switch (p.photo.status) {
      case PhotoStatus.pending:
        gate(f, '${p.id}: photo is pending (needs an image and attribution)');
      case PhotoStatus.ready:
        if (p.photo.asset == null) {
          error(f, '${p.id}: photo is ready but has no asset path');
        }
        if (p.photo.attribution == null) {
          error(f, '${p.id}: photo has no attribution string');
        }
    }
  }

  // --- bird <-> plant links ----------------------------------------------
  final linkedBirds = <String>{};
  final linkedPlants = <String>{};
  final pairs = <String>{};
  for (final l in repo.links) {
    final f = 'bird_plant.json';
    final label = '${l.birdId}/${l.plantId}';
    if (repo.birdById(l.birdId) == null) {
      error(f, '$label: unknown bird "${l.birdId}"');
    } else {
      linkedBirds.add(l.birdId);
    }
    if (repo.plantById(l.plantId) == null) {
      error(f, '$label: unknown plant "${l.plantId}"');
    } else {
      linkedPlants.add(l.plantId);
    }
    if (!pairs.add(label)) error(f, '$label: duplicate link');
    if (l.weight < 1 || l.weight > 3) error(f, '$label: weight must be 1-3');
    if (l.needs.isEmpty) error(f, '$label: needs must not be empty');
  }
  for (final b in repo.birds) {
    if (!linkedBirds.contains(b.id)) {
      error('bird_plant.json', '${b.id}: bird has zero plant links');
    }
  }
  for (final p in repo.plants) {
    if (!linkedPlants.contains(p.id)) {
      warning('bird_plant.json', '${p.id}: plant is not linked to any bird');
    }
  }

  // --- actions and tips ---------------------------------------------------
  for (final a in repo.actions) {
    if (a.months.isEmpty || a.months.any((m) => m < 1 || m > 12)) {
      error('actions.json', '${a.id}: months must be a non-empty list of 1-12');
    }
    for (final id in a.relatedPlantIds) {
      if (repo.plantById(id) == null) {
        error('actions.json', '${a.id}: unknown related plant "$id"');
      }
    }
  }
  final tipMonths = <int>{};
  for (final t in repo.tips) {
    if (t.months.isEmpty || t.months.any((m) => m < 1 || m > 12)) {
      error('tips.json', '${t.id}: months must be a non-empty list of 1-12');
    }
    tipMonths.addAll(t.months);
    for (final id in t.relatedActionIds) {
      if (repo.actionById(id) == null) {
        error('tips.json', '${t.id}: unknown related action "$id"');
      }
    }
  }
  final missing = [
    for (var m = 1; m <= 12; m++)
      if (!tipMonths.contains(m)) m
  ];
  if (missing.isNotEmpty) {
    error('tips.json', 'no tip for month(s) ${missing.join(', ')}');
  }

  // --- aliases ------------------------------------------------------------
  // Same normalizer as the resolver, so a collision found here is a collision
  // the resolver would have hit.
  final owner = <String, String>{}; // normalized name -> taxonId
  void claim(String name, String taxonId, String source) {
    final key = normalizeName(name);
    final cleaned = parseFreeText(name).name;
    if (key.isEmpty) {
      error('taxonomy_aliases.json', '$taxonId: empty name from $source');
      return;
    }
    if (cleaned != key) {
      error('taxonomy_aliases.json',
          '$taxonId: "$name" would be altered to "$cleaned" before lookup, so it can never match');
    }
    final existing = owner[key];
    if (existing != null && existing != taxonId) {
      error('taxonomy_aliases.json',
          '"$name" maps to both $existing and $taxonId');
    }
    owner[key] = taxonId;
  }

  for (final b in repo.birds) {
    claim(b.commonName, b.id, 'birds.json commonName');
    claim(b.scientificName, b.id, 'birds.json scientificName');
  }
  for (final entry in repo.aliases.aliases.entries) {
    if (repo.birdById(entry.key) == null) {
      error(
          'taxonomy_aliases.json', 'alias set for unknown bird "${entry.key}"');
      continue;
    }
    for (final n in entry.value) {
      claim(n, entry.key, 'taxonomy_aliases.json');
    }
  }
  final notSpecies = {
    ...repo.aliases.notABird.map(normalizeName),
    ...repo.aliases.noSpeciesPhrases.map(normalizeName),
  };
  for (final key in owner.keys) {
    if (notSpecies.contains(key)) {
      error('taxonomy_aliases.json',
          '"$key" is both a bird name (${owner[key]}) and a non-bird/no-species phrase');
    }
  }

  return ValidationReport(issues);
}
