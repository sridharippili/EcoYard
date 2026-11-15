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
  PlantFinderController({
    required AppContent content,
    required this.now,
    required this._settings,
  }) : _content = content,
       _finder = PlantFinder(content.repo) {
    final d = _settings();
    space = d.defaultSpace;
    sun = d.defaultSun;
    budget = d.defaultBudget;
    _recompute();
  }

  final AppSettings Function() _settings;

  /// True once the user has changed a filter on this screen.
  bool touched = false;

  final AppContent _content;
  final PlantFinder _finder;
  final DateTime Function() now;

  late SpaceType space;
  late SunExposure sun;
  late BudgetTier budget;

  late PlantFinderResult result;

  /// A free action for these choices this month, or null when none is in
  /// season. The only part of the screen that depends on the date.
  HabitatAction? freeFirstStep;

  void setSpace(SpaceType v) => _set(() {
    touched = true;
    space = v;
  });
  void setSun(SunExposure v) => _set(() {
    touched = true;
    sun = v;
  });
  void setBudget(BudgetTier v) => _set(() {
    touched = true;
    budget = v;
  });

  /// Settings finished loading after this screen was built: adopt them, but
  /// only if the user has not already picked something here.
  void adoptDefaultsIfUntouched() {
    if (!touched) showDefaults();
  }

  /// "Find Native Plants", My Plan's link, and saving new defaults: back to
  /// the user's own starting choices (Settings).
  void showDefaults() => _set(() {
    final d = _settings();
    touched = false;
    space = d.defaultSpace;
    sun = d.defaultSun;
    budget = d.defaultBudget;
  });

  /// "Small Space": balcony for this visit only (never saved), everything
  /// else from the user's defaults.
  void showSmallSpace() => _set(() {
    final d = _settings();
    touched = false;
    space = SpaceType.balcony;
    sun = d.defaultSun;
    budget = d.defaultBudget;
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
