import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:flutter/foundation.dart';

import '../../app/content.dart';

/// Filters and results for the Plants tab. Owned by the Shell so Home tiles
/// and My Plan can open the tab with a chosen starting point.
///
/// Rules: the tab bar's Plants button leaves the filters as the user left
/// them. "Find Native Plants" ([showDefaults]) and the plan's "See native
/// plants" always start from the defaults; "Small Space" ([showSmallSpace])
/// starts on Balcony. Each is an explicit action, so a preset never sticks
/// by accident.
class PlantFinderController extends ChangeNotifier {
  PlantFinderController({required AppContent content, required this.now})
    : _content = content,
      _finder = PlantFinder(content.repo) {
    _recompute();
  }

  static const defaultSpace = SpaceType.yard;
  static const defaultSun = SunExposure.full;
  static const defaultBudget = BudgetTier.any;

  final AppContent _content;
  final PlantFinder _finder;
  final DateTime Function() now;

  SpaceType space = defaultSpace;
  SunExposure sun = defaultSun;
  BudgetTier budget = defaultBudget;

  late PlantFinderResult result;

  /// A free action for these choices this month, or null when none is in
  /// season. The only part of the screen that depends on the date.
  HabitatAction? freeFirstStep;

  void setSpace(SpaceType v) => _set(() => space = v);
  void setSun(SunExposure v) => _set(() => sun = v);
  void setBudget(BudgetTier v) => _set(() => budget = v);

  /// "Find Native Plants": back to the starting choices.
  void showDefaults() => _set(() {
    space = defaultSpace;
    sun = defaultSun;
    budget = defaultBudget;
  });

  /// "Small Space": balcony, everything else back to the defaults.
  void showSmallSpace() => _set(() {
    space = SpaceType.balcony;
    sun = defaultSun;
    budget = defaultBudget;
  });

  void _set(VoidCallback change) {
    change();
    _recompute();
    notifyListeners();
  }

  void _recompute() {
    result = _finder.find(PlantFilter(space: space, sun: sun, budget: budget));
    freeFirstStep = _content.engine
        .recommend(
          HabitatQuery(
            birdId: null,
            space: space,
            sun: sun,
            budget: budget,
            month: now().month,
            regionCode: _content.repo.region,
          ),
        )
        .freeFirstStep;
  }

  FinderPlant describe(String plantId) => _finder.describe(plantId);
}
