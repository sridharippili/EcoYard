import 'dart:convert';
import 'dart:io';

import 'package:ecoyard_core/ecoyard_core.dart';

/// Finds the repo root (the folder holding `content/`) from wherever the
/// tests run, because pre-push runs each package from its own directory.
Directory repoRoot() {
  var dir = Directory.current.absolute;
  for (var i = 0; i < 8; i++) {
    if (File('${dir.path}/content/birds.json').existsSync()) return dir;
    dir = dir.parent;
  }
  throw StateError(
      'Could not find content/birds.json above ${Directory.current}');
}

String _read(String name) =>
    File('${repoRoot().path}/content/$name').readAsStringSync();

/// The real bundled content, as text.
ContentFiles realContent() => ContentFiles(
      birds: _read('birds.json'),
      plants: _read('plants.json'),
      birdPlant: _read('bird_plant.json'),
      actions: _read('actions.json'),
      tips: _read('tips.json'),
      aliases: _read('taxonomy_aliases.json'),
    );

/// The real content with one file edited. [edit] receives the decoded JSON
/// and changes it in place.
ContentFiles withEdit(
  String file,
  void Function(Map<String, dynamic> json) edit,
) {
  final c = realContent();
  String apply(String text) {
    final json = jsonDecode(text) as Map<String, dynamic>;
    edit(json);
    return jsonEncode(json);
  }

  return ContentFiles(
    birds: file == 'birds' ? apply(c.birds) : c.birds,
    plants: file == 'plants' ? apply(c.plants) : c.plants,
    birdPlant: file == 'bird_plant' ? apply(c.birdPlant) : c.birdPlant,
    actions: file == 'actions' ? apply(c.actions) : c.actions,
    tips: file == 'tips' ? apply(c.tips) : c.tips,
    aliases: file == 'aliases' ? apply(c.aliases) : c.aliases,
  );
}

SpeciesResolver realResolver() =>
    SpeciesResolver(ReferenceRepository.fromJson(realContent()));
