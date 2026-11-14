// Prints a habitat recommendation for a bird, from the command line.
//
//   dart run scripts/recommend.dart "Northern Cardinal"
//   dart run scripts/recommend.dart "blue jays" --month 10 --sun partial \
//       --space yard --budget low --journal "Carolina Wren,American Robin"
//
// Options (all optional):
//   --month N        1-12, default: this month
//   --sun S          full | partial | shade   (default partial)
//   --space S        yard | balcony | containers   (default yard)
//   --budget B       free | low | any   (default low)
//   --journal A,B    birds you have already identified
//
// Uses the same species resolver and HabitatEngine as the app, over the
// bundled content/ files. Imported by relative path because this script has no
// pubspec of its own.

import 'dart:io';

import '../packages/ecoyard_core/lib/src/habitat_engine.dart';
import '../packages/ecoyard_core/lib/src/models.dart';
import '../packages/ecoyard_core/lib/src/reference_repository.dart';
import '../packages/ecoyard_core/lib/src/species_resolver.dart';

void main(List<String> args) {
  final positional = <String>[];
  final opts = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a.startsWith('--')) {
      if (i + 1 >= args.length) _fail('${a} needs a value');
      opts[a.substring(2)] = args[++i];
    } else {
      positional.add(a);
    }
  }
  if (positional.isEmpty) {
    _fail('Give a bird name, e.g. dart run scripts/recommend.dart "Blue Jay"');
  }

  final root = File.fromUri(Platform.script).parent.parent;
  String read(String n) => File('${root.path}/content/$n').readAsStringSync();
  final repo = ReferenceRepository.fromJson(
    ContentFiles(
      birds: read('birds.json'),
      plants: read('plants.json'),
      birdPlant: read('bird_plant.json'),
      actions: read('actions.json'),
      tips: read('tips.json'),
      aliases: read('taxonomy_aliases.json'),
    ),
  );
  final resolver = SpeciesResolver(repo);
  final engine = HabitatEngine(repo);

  T pick<T>(List<T> values, String Function(T) name, String key, T fallback) {
    final v = opts[key];
    if (v == null) return fallback;
    for (final e in values) {
      if (name(e) == v) return e;
    }
    _fail('--$key must be one of ${values.map(name).join(', ')}');
  }

  final month = int.tryParse(opts['month'] ?? '') ?? DateTime.now().month;
  final space = pick(SpaceType.values, (e) => e.json, 'space', SpaceType.yard);
  final sun = pick(
    SunExposure.values,
    (e) => e.json,
    'sun',
    SunExposure.partial,
  );
  final budget = pick(
    BudgetTier.values,
    (e) => e.json,
    'budget',
    BudgetTier.low,
  );

  final match = resolver.resolve(rawName: positional.join(' '));
  if (!match.isBird) {
    stdout.writeln(
      '"${match.displayName}" is not a bird, so there is nothing to recommend.',
    );
    return;
  }

  final journal = <String>{};
  for (final name in (opts['journal'] ?? '').split(',')) {
    if (name.trim().isEmpty) continue;
    final j = resolver.resolve(rawName: name);
    if (j.isResolved) {
      journal.add(j.taxonId!);
    } else {
      stderr.writeln('(journal: "$name" is not in our content, ignored)');
    }
  }

  final rec = engine.recommend(
    HabitatQuery(
      birdId: match.taxonId,
      space: space,
      sun: sun,
      budget: budget,
      month: month,
      regionCode: repo.region,
      journalBirdIds: journal,
    ),
  );

  stdout.writeln('');
  if (rec.isGeneric) {
    stdout.writeln('"${match.displayName}": no habitat tips for this one yet.');
    stdout.writeln('Showing advice that helps most birds.');
  } else {
    stdout.writeln(
      '${match.displayName}  (${match.scientificName})  '
      'matched by ${match.source.name}, confidence ${match.confidence.name}',
    );
  }
  stdout.writeln(
    'Month $month · ${space.json} · ${sun.json} sun · budget ${budget.json}'
    '${journal.isEmpty ? '' : ' · journal: ${journal.join(', ')}'}',
  );

  if (rec.supportNeeds.isNotEmpty) {
    stdout.writeln('\nWhat this bird needs');
    for (final n in rec.supportNeeds) {
      final remedy = n.hasRemedy
          ? '${n.remedyActionIds.length} action(s), ${n.remedyPlantIds.length} plant(s)'
          : 'nothing in our content can help with this right now';
      stdout.writeln('  ${n.need.json.padRight(8)} ${n.why}');
      stdout.writeln('           -> $remedy');
      if (!n.hasRemedy) {
        if (n.moreBudgetActionIds.isNotEmpty) {
          stdout.writeln(
            '              (a small budget would unlock: ${n.moreBudgetActionIds.join(', ')})',
          );
        }
        if (n.laterActionIds.isNotEmpty) {
          stdout.writeln(
            '              (out of season now, try later: ${n.laterActionIds.join(', ')})',
          );
        }
      } else if (!n.coveredByShownActions && n.remedyPlantIds.isEmpty) {
        stdout.writeln(
          '              (also possible: ${n.remedyActionIds.join(', ')})',
        );
      }
    }
  }

  stdout.writeln('\nDo this (${rec.actions.length}, free first)');
  if (rec.actions.isEmpty)
    stdout.writeln('  (no actions fit this month, space and budget)');
  for (final a in rec.actions) {
    stdout.writeln('  [${a.costTier.json}] ${a.title}');
    stdout.writeln('         ${a.body}');
  }

  stdout.writeln('\nPlants');
  if (rec.plants.isEmpty) {
    stdout.writeln(
      budget == BudgetTier.free
          ? '  (a free budget leaves plants out)'
          : '  (no plant fits this sun and space)',
    );
  }
  for (final p in rec.plants) {
    final also = p.alsoHelps.isEmpty
        ? ''
        : '   also helps: ${p.alsoHelps.join(', ')}';
    stdout.writeln('  ${p.plant.commonName}  [score ${p.score}]$also');
    if (p.reason != null) stdout.writeln('         ${p.reason}');
  }
  if (rec.plantsHiddenByFilters > 0 && budget != BudgetTier.free) {
    stdout.writeln(
      '  (${rec.plantsHiddenByFilters} more would help with different sun or space)',
    );
  }
  stdout.writeln('');
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(64);
}
