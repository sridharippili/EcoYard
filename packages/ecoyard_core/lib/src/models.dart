/// Content models. Plain data, no platform or UI types.
library;

/// Thrown when a content file is malformed.
class ContentFormatException implements Exception {
  const ContentFormatException(this.file, this.message);

  final String file;
  final String message;

  @override
  String toString() => 'ContentFormatException($file: $message)';
}

enum Need {
  food('food'),
  shelter('shelter'),
  water('water'),
  nesting('nesting'),
  safety('safety');

  const Need(this.json);
  final String json;
}

enum SunExposure {
  full('full'),
  partial('partial'),
  shade('shade');

  const SunExposure(this.json);
  final String json;
}

enum WaterNeed {
  low('low'),
  medium('medium'),
  high('high');

  const WaterNeed(this.json);
  final String json;
}

enum PlantType {
  perennial('perennial'),
  shrub('shrub'),
  tree('tree'),
  vine('vine'),
  grass('grass');

  const PlantType(this.json);
  final String json;
}

/// Where a plant is native, relative to the content region.
enum Nativity {
  /// Native across the content region (shown as "NJ native" etc.).
  nativeToRegion('native-to-region'),

  /// Native to the eastern US but not everywhere in the region
  /// (shown as "Eastern US native").
  easternUs('eastern-us');

  const Nativity(this.json);
  final String json;
}

enum PlantBenefit {
  seeds('seeds'),
  nectar('nectar'),
  berries('berries'),
  cover('cover'),
  hostPlant('host-plant'),
  nestingMaterial('nesting-material');

  const PlantBenefit(this.json);
  final String json;
}

enum SpaceType {
  yard('yard'),
  balcony('balcony'),
  containers('containers');

  const SpaceType(this.json);
  final String json;
}

enum CostTier {
  free('free'),
  low('low');

  const CostTier(this.json);
  final String json;
}

enum ReviewStatus {
  /// Written by Claude or a first pass. Must be reviewed before release.
  draft('draft'),
  reviewed('reviewed');

  const ReviewStatus(this.json);
  final String json;
}

enum PhotoStatus {
  pending('pending'),
  ready('ready');

  const PhotoStatus(this.json);
  final String json;
}

class SupportNeed {
  const SupportNeed({required this.need, required this.why});

  final Need need;
  final String why;
}

class Bird {
  const Bird({
    required this.id,
    required this.scientificName,
    required this.commonName,
    required this.supportNeeds,
  });

  /// Stable taxon key: the eBird species code, e.g. `norcar`.
  final String id;
  final String scientificName;
  final String commonName;
  final List<SupportNeed> supportNeeds;
}

class PlantPhoto {
  const PlantPhoto({required this.status, this.asset, this.attribution});

  final PhotoStatus status;

  /// Bundled asset path, e.g. `assets/plants/black-eyed-susan.jpg`.
  final String? asset;

  /// Credit line for the credits screen, e.g. author and licence.
  final String? attribution;
}

class Plant {
  const Plant({
    required this.id,
    required this.commonName,
    required this.scientificName,
    required this.plantType,
    required this.nativity,
    required this.sun,
    required this.water,
    required this.heightFtMin,
    required this.heightFtMax,
    required this.bloomStartMonth,
    required this.bloomEndMonth,
    required this.benefits,
    required this.spaces,
    required this.costTier,
    required this.photo,
    this.note,
  });

  final String id;
  final String commonName;
  final String scientificName;
  final PlantType plantType;
  final Nativity nativity;
  final List<SunExposure> sun;
  final WaterNeed water;
  final int heightFtMin;
  final int heightFtMax;
  final int bloomStartMonth;
  final int bloomEndMonth;
  final List<PlantBenefit> benefits;
  final List<SpaceType> spaces;
  final CostTier costTier;
  final PlantPhoto photo;
  final String? note;
}

class BirdPlantLink {
  const BirdPlantLink({
    required this.birdId,
    required this.plantId,
    required this.weight,
    required this.needs,
    required this.reason,
  });

  final String birdId;
  final String plantId;

  /// 3 = a main reason to plant it for this bird, 1 = a bonus.
  final int weight;
  final List<Need> needs;
  final String reason;
}

class HabitatAction {
  const HabitatAction({
    required this.id,
    required this.title,
    required this.body,
    required this.costTier,
    required this.months,
    required this.spaces,
    required this.needs,
    required this.relatedPlantIds,
  });

  final String id;
  final String title;
  final String body;
  final CostTier costTier;

  /// Months (1-12) in which the action makes sense.
  final List<int> months;
  final List<SpaceType> spaces;
  final List<Need> needs;
  final List<String> relatedPlantIds;
}

class Tip {
  const Tip({
    required this.id,
    required this.months,
    required this.text,
    required this.relatedActionIds,
  });

  final String id;
  final List<int> months;
  final String text;
  final List<String> relatedActionIds;
}

/// Names that map to a taxon, plus names that are not birds.
class AliasTable {
  const AliasTable({
    required this.aliases,
    required this.notABird,
    required this.noSpeciesPhrases,
  });

  /// taxonId -> names as written in the file (not yet normalized).
  final Map<String, List<String>> aliases;

  /// BirdNET's non-bird classes, e.g. "Human vocal", "Gun".
  final List<String> notABird;

  /// Free-text answers that mean "no bird", e.g. "unknown".
  final List<String> noSpeciesPhrases;
}
