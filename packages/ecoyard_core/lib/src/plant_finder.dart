import 'habitat_engine.dart' show BudgetTier;
import 'models.dart';
import 'reference_repository.dart';

/// What the user chose in the Plant Finder.
class PlantFilter {
  const PlantFilter({
    required this.space,
    required this.sun,
    required this.budget,
  });

  final SpaceType space;
  final SunExposure sun;
  final BudgetTier budget;

  @override
  bool operator ==(Object other) =>
      other is PlantFilter &&
      other.space == space &&
      other.sun == sun &&
      other.budget == budget;

  @override
  int get hashCode => Object.hash(space, sun, budget);
}

/// One plant in the results, with the birds it helps (strongest link first).
class FinderPlant {
  const FinderPlant({
    required this.plant,
    required this.birds,
    required this.breadth,
  });

  final Plant plant;

  /// Birds this plant is linked to: higher link weight first, then bird id,
  /// so the order never depends on the order of the JSON file.
  final List<Bird> birds;

  /// Sum of the plant's link weights. A plant with no links has 0.
  final int breadth;
}

class PlantFinderResult {
  const PlantFinderResult({
    required this.plants,
    required this.hiddenCount,
    required this.totalCount,
    required this.noPlantIsFree,
  });

  /// Plants that fit the filter, best first.
  final List<FinderPlant> plants;

  /// Plants in the content that the filter removed.
  final int hiddenCount;

  /// Every plant in the content.
  final int totalCount;

  /// True when no plant in the content has [CostTier.free]. Lets the screen
  /// say "no plant in this list is free" instead of a vague "nothing found".
  final bool noPlantIsFree;
}

/// Lists and ranks plants for the Plant Finder. Pure: no clock, no I/O.
///
/// It walks every plant in the content, not the bird-plant links, so a plant
/// that no bird is linked to (yet) is still listed, just ranked last.
///
/// Budget rule: a plant is shown when its own `costTier` is allowed by the
/// budget (`free` only lets free plants through). Today every plant is `low`,
/// so "Free only" shows none. This differs deliberately from the bird advice
/// in HabitatEngine, which never offers plants on a free budget.
class PlantFinder {
  PlantFinder(this._repo);

  final ReferenceRepository _repo;

  PlantFinderResult find(PlantFilter f) {
    final all = _repo.plants;
    final shown = [
      for (final p in all)
        if (p.sun.contains(f.sun) &&
            p.spaces.contains(f.space) &&
            f.budget.allows(p.costTier))
          _describe(p),
    ];
    shown.sort((a, b) {
      final byBreadth = b.breadth.compareTo(a.breadth);
      if (byBreadth != 0) return byBreadth;
      final byCost = a.plant.costTier.index.compareTo(b.plant.costTier.index);
      if (byCost != 0) return byCost;
      return a.plant.id.compareTo(b.plant.id);
    });
    return PlantFinderResult(
      plants: shown,
      hiddenCount: all.length - shown.length,
      totalCount: all.length,
      noPlantIsFree: all.every((p) => p.costTier != CostTier.free),
    );
  }

  /// A plant with its birds, whether or not it passes any filter.
  FinderPlant describe(String plantId) {
    final p = _repo.plantById(plantId);
    if (p == null) throw ArgumentError.value(plantId, 'plantId', 'unknown');
    return _describe(p);
  }

  FinderPlant _describe(Plant p) {
    final links = [..._repo.linksForPlant(p.id)]..sort((a, b) {
        final byWeight = b.weight.compareTo(a.weight);
        return byWeight != 0 ? byWeight : a.birdId.compareTo(b.birdId);
      });
    return FinderPlant(
      plant: p,
      birds: [
        for (final l in links)
          if (_repo.birdById(l.birdId) != null) _repo.birdById(l.birdId)!,
      ],
      breadth: links.fold(0, (sum, l) => sum + l.weight),
    );
  }
}
