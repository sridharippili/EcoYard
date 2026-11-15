import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:flutter/services.dart' show rootBundle;

/// The reference content and the things built from it, loaded once.
class AppContent {
  AppContent(this.repo)
    : resolver = SpeciesResolver(repo),
      engine = HabitatEngine(repo);

  final ReferenceRepository repo;
  final SpeciesResolver resolver;
  final HabitatEngine engine;

  /// True while ANY content file is still a draft. Screens that mix files
  /// (plants + actions + tips) show draft wording until all are reviewed.
  bool get isDraft => repo.reviewStatus == ReviewStatus.draft;
}

/// Reads `assets/content/*.json` (copies of the repo's `content/`, kept equal
/// by `scripts/sync_content.sh` and a test). Throws if a file is missing or
/// malformed; the app then shows a retry screen, never a half-working app.
Future<AppContent> loadBundledContent() async {
  Future<String> read(String name) =>
      rootBundle.loadString('assets/content/$name');
  final files = ContentFiles(
    birds: await read('birds.json'),
    plants: await read('plants.json'),
    birdPlant: await read('bird_plant.json'),
    actions: await read('actions.json'),
    tips: await read('tips.json'),
    aliases: await read('taxonomy_aliases.json'),
  );
  return AppContent(ReferenceRepository.fromJson(files));
}
