import 'package:ecoyard_core/ecoyard_core.dart';

/// Words for the content's enums. Display text only; the facts live in
/// `content/*.json`.

const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
];

String monthName(int m) => _monthNames[(m - 1) % 12];

/// "Jun–Oct", or "Nov–Mar" when the bloom runs over the new year, or just
/// "Jun" for a one-month bloom. Static facts about the plant: never "now".
String bloomRange(Plant p) {
  final a = monthName(p.bloomStartMonth), b = monthName(p.bloomEndMonth);
  return p.bloomStartMonth == p.bloomEndMonth ? a : '$a–$b';
}

String benefitLabel(PlantBenefit b) => switch (b) {
  PlantBenefit.seeds => 'Seeds',
  PlantBenefit.nectar => 'Nectar',
  PlantBenefit.berries => 'Berries',
  PlantBenefit.cover => 'Cover',
  PlantBenefit.hostPlant => 'Caterpillar host',
  PlantBenefit.nestingMaterial => 'Nesting material',
};

/// What the plant's `nativity` value supports. Never a state name.
String nativityLabel(Nativity n) => switch (n) {
  Nativity.nativeToRegion => 'Native to the Northeast',
  Nativity.easternUs => 'Eastern US native',
};

String sunLabel(SunExposure s) => switch (s) {
  SunExposure.full => 'Full sun',
  SunExposure.partial => 'Part shade',
  SunExposure.shade => 'Shade',
};

String spaceLabel(SpaceType s) => switch (s) {
  SpaceType.yard => 'Yard',
  SpaceType.balcony => 'Balcony',
  SpaceType.containers => 'Containers',
};

String waterLabel(WaterNeed w) => switch (w) {
  WaterNeed.low => 'Low water',
  WaterNeed.medium => 'Medium water',
  WaterNeed.high => 'High water',
};

String plantTypeLabel(PlantType t) => switch (t) {
  PlantType.perennial => 'Perennial',
  PlantType.shrub => 'Shrub',
  PlantType.tree => 'Tree',
  PlantType.vine => 'Vine',
  PlantType.grass => 'Grass',
};

String plantCostLabel(CostTier c) => c == CostTier.free ? 'Free' : 'Low cost';

String heightLabel(Plant p) => p.heightFtMin == p.heightFtMax
    ? '${p.heightFtMin} ft'
    : '${p.heightFtMin}–${p.heightFtMax} ft';

/// Region codes to words. Unknown codes are shown as they are.
String regionLabel(String code) => switch (code) {
  'us-ne' => 'Northeast US',
  _ => code,
};

/// "Seeds, nectar · helps Northern Cardinal, American Goldfinch"
String supportLine(FinderPlant p, {int maxBirds = 2}) {
  final what = p.plant.benefits.map(benefitLabel).join(', ');
  final birds = p.birds.take(maxBirds).map((b) => b.commonName).join(', ');
  if (birds.isEmpty) return what;
  return '$what · helps $birds';
}
