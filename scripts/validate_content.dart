// Validates content/*.json. Run from anywhere:
//
//   dart run scripts/validate_content.dart            # normal
//   dart run scripts/validate_content.dart --strict   # release gate
//
// Normal mode fails on real mistakes (dangling ids, duplicate aliases, bad
// schema). --strict also fails on unfinished work: draft review status and
// pending plant photos. Exit code 1 on any error.
//
// The checks live in packages/ecoyard_core so the resolver and this script
// share one normalizer. They are imported by relative path because this script
// has no pubspec of its own.

import 'dart:io';

import '../packages/ecoyard_core/lib/src/content_validator.dart';
import '../packages/ecoyard_core/lib/src/reference_repository.dart';

void main(List<String> args) {
  final strict = args.contains('--strict');
  final root = File.fromUri(Platform.script).parent.parent;
  final dir = Directory('${root.path}/content');

  String read(String name) {
    final f = File('${dir.path}/$name');
    if (!f.existsSync()) {
      stderr.writeln('ERROR $name: file is missing from ${dir.path}');
      exit(1);
    }
    return f.readAsStringSync();
  }

  final report = validateContent(
    ContentFiles(
      birds: read('birds.json'),
      plants: read('plants.json'),
      birdPlant: read('bird_plant.json'),
      actions: read('actions.json'),
      tips: read('tips.json'),
      aliases: read('taxonomy_aliases.json'),
    ),
    strict: strict,
  );

  for (final w in report.warnings) {
    stdout.writeln(w);
  }
  for (final e in report.errors) {
    stderr.writeln(e);
  }

  final mode = strict ? 'strict' : 'normal';
  if (report.ok) {
    stdout.writeln('content OK ($mode): ${report.warnings.length} warning(s)');
  } else {
    stderr.writeln(
      'content FAILED ($mode): ${report.errors.length} error(s), '
      '${report.warnings.length} warning(s)',
    );
    exit(1);
  }
}
