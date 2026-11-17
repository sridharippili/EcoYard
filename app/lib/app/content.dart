import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:flutter/services.dart' show rootBundle;

/// The reference content and the things built from it, loaded once.
class AppContent {
  AppContent(this.repo, {PhotoCredits? photos})
    : resolver = SpeciesResolver(repo),
      engine = HabitatEngine(repo),
      photos = photos ?? PhotoCredits.empty();

  final ReferenceRepository repo;

  /// The species photos we ship, with their credits. Empty when the file is
  /// missing: the screens then show their placeholder rather than nothing.
  final PhotoCredits photos;
  final SpeciesResolver resolver;
  final HabitatEngine engine;

  /// True while ANY content file is still a draft. Screens that mix files
  /// (plants + actions + tips) show draft wording until all are reviewed.
  bool get isDraft => repo.reviewStatus == ReviewStatus.draft;
}

/// The offline model's settings and download addresses. Never throws: if the
/// file is missing or unreadable the feature is simply not offered.
Future<OfflineModelConfig> loadOfflineModelConfig() async {
  try {
    return OfflineModelConfig.parse(
      await rootBundle.loadString('assets/content/offline_model.json'),
    );
  } catch (_) {
    return OfflineModelConfig.none;
  }
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
  PhotoCredits photos;
  try {
    photos = PhotoCredits.fromJson(await read('photo_credits.json'));
  } catch (_) {
    // Missing or malformed credits must not stop the app: no credit means
    // no photo, and the placeholders take over.
    photos = PhotoCredits.empty();
  }
  return AppContent(ReferenceRepository.fromJson(files), photos: photos);
}
