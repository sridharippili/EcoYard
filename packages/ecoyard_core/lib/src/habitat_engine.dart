/// Turns "which bird" plus "what is your space" into a short, ranked list of
/// things to do and plants to add. Pure logic: no I/O, no clock (the month is
/// an input), no randomness, so the same input always gives the same answer.
///
/// The ranking rules are written in prose in docs/ENGINE_SPEC.md and pinned by
/// the cases in fixtures/engine_cases.json.
library;

import 'models.dart';
import 'reference_repository.dart';

/// How much the user is willing to spend.
enum BudgetTier {
  /// Only free actions. No plants (every plant costs something).
  free('free'),

  /// Free and low-cost things.
  low('low'),

  /// Everything.
  any('any');

  const BudgetTier(this.json);
  final String json;

  bool allows(CostTier cost) => switch (this) {
        BudgetTier.free => cost == CostTier.free,
        BudgetTier.low || BudgetTier.any => true,
      };

  bool get allowsPlants => this != BudgetTier.free;
}

/// Thrown for a region this content does not cover.
class UnsupportedRegionException implements Exception {
  const UnsupportedRegionException(this.requested, this.supported);

  final String requested;
  final String supported;

  @override
  String toString() =>
      'UnsupportedRegionException($requested; content covers $supported)';
}

/// Everything the engine needs to know.
class HabitatQuery {
  const HabitatQuery({
    required this.birdId,
    required this.space,
    required this.sun,
    required this.budget,
    required this.month,
    required this.regionCode,
    this.journalBirdIds = const {},
  });

  /// The resolved species, or null when the species is unknown (then the
  /// answer is generic advice that helps most birds).
  final String? birdId;
  final SpaceType space;
  final SunExposure sun;
  final BudgetTier budget;

  /// 1-12.
  final int month;
  final String regionCode;

  /// Birds the user has already identified. Plants that help several of them
  /// rank higher.
  final Set<String> journalBirdIds;
}

/// One of a bird's needs, and what could be done about it right now.
class NeedCoverage {
  const NeedCoverage({
    required this.need,
    required this.why,
    required this.remedyActionIds,
    required this.shownActionIds,
    required this.laterActionIds,
    required this.moreBudgetActionIds,
    required this.remedyPlantIds,
  });

  final Need need;
  final String why;

  /// Every action available this month (not only the three shown) that
  /// addresses this need, best first.
  final List<String> remedyActionIds;

  /// The part of [remedyActionIds] that is among the actions shown.
  final List<String> shownActionIds;

  /// Actions that would address this need but are out of season this month.
  /// The UI can say "try this in spring".
  final List<String> laterActionIds;

  /// Actions in season that fit the space and bird but cost more than the
  /// budget allows. The UI can say "a small budget would unlock this".
  final List<String> moreBudgetActionIds;

  /// Every eligible plant that addresses this need for this bird, best first.
  final List<String> remedyPlantIds;

  /// True when at least one of the three shown actions addresses this need.
  /// A need that has a remedy but is not covered by what is shown is
  /// "also possible", not "nothing to do".
  bool get coveredByShownActions => shownActionIds.isNotEmpty;

  /// False when nothing available now, within this budget, space and season,
  /// can help. The UI must then say so, and point at [laterActionIds] or
  /// [moreBudgetActionIds] when they are not empty, rather than claim that
  /// nothing can be done.
  bool get hasRemedy => remedyActionIds.isNotEmpty || remedyPlantIds.isNotEmpty;
}

class RankedPlant {
  const RankedPlant({
    required this.plant,
    required this.score,
    required this.alsoHelps,
    this.reason,
  });

  final Plant plant;
  final int score;

  /// Why it helps this bird. Null in generic mode.
  final String? reason;

  /// Journal birds this plant also supports.
  final List<String> alsoHelps;
}

class HabitatRecommendation {
  const HabitatRecommendation({
    required this.birdId,
    required this.isGeneric,
    required this.supportNeeds,
    required this.actions,
    required this.plants,
    required this.plantsHiddenByFilters,
  });

  /// Null in generic mode.
  final String? birdId;

  /// True when the species was unknown, so this is advice for birds in general.
  final bool isGeneric;

  final List<NeedCoverage> supportNeeds;

  /// Ranked, at most [HabitatEngine.maxActions].
  final List<HabitatAction> actions;

  /// All eligible plants, best first. The UI shows as many as it has room for.
  final List<RankedPlant> plants;

  /// Plants that would help but were removed by sun, space or budget.
  final int plantsHiddenByFilters;

  /// The first free action, if any. The mockup's "Free first step".
  HabitatAction? get freeFirstStep {
    for (final a in actions) {
      if (a.costTier == CostTier.free) return a;
    }
    return null;
  }

  /// Needs nothing can address (given this space, month and budget).
  List<Need> get unmetNeeds => [
        for (final n in supportNeeds)
          if (!n.hasRemedy) n.need
      ];
}

class HabitatEngine {
  HabitatEngine(this._repo);

  /// "Never more than three actions at once." The mockup gets this right.
  static const int maxActions = 3;

  final ReferenceRepository _repo;

  HabitatRecommendation recommend(HabitatQuery q) {
    if (q.month < 1 || q.month > 12) {
      throw ArgumentError.value(q.month, 'month', 'must be 1-12');
    }
    if (q.regionCode != _repo.region) {
      throw UnsupportedRegionException(q.regionCode, _repo.region);
    }
    final bird = q.birdId == null ? null : _repo.birdById(q.birdId!);
    if (q.birdId != null && bird == null) {
      throw ArgumentError.value(q.birdId, 'birdId', 'is not in the content');
    }

    final needs = bird?.supportNeeds ?? const <SupportNeed>[];
    // Unknown bird: aim for a spread across every kind of need.
    final target =
        bird != null ? {for (final n in needs) n.need} : Need.values.toSet();

    // Actions that suit the space, budget and bird, in or out of season.
    final suited = _repo.actions
        .where((a) =>
            a.spaces.contains(q.space) &&
            (a.forBirdIds.isEmpty ||
                (bird != null && a.forBirdIds.contains(bird.id))))
        .toList();
    final applicable =
        suited.where((a) => q.budget.allows(a.costTier)).toList();
    final moreBudget = suited
        .where(
            (a) => !q.budget.allows(a.costTier) && a.months.contains(q.month))
        .toList()
      ..sort(_staticOrder);
    final eligible = applicable
        .where((a) => a.months.contains(q.month))
        .toList()
      ..sort(_staticOrder);
    final later = applicable.where((a) => !a.months.contains(q.month)).toList()
      ..sort(_staticOrder);

    final shown = _select(eligible, target, bird?.id);
    final shownIds = {for (final a in shown) a.id};
    final plants = _rankPlants(q);

    return HabitatRecommendation(
      birdId: bird?.id,
      isGeneric: bird == null,
      supportNeeds: [
        for (final n in needs)
          NeedCoverage(
            need: n.need,
            why: n.why,
            remedyActionIds: [
              for (final a in eligible)
                if (a.needs.contains(n.need)) a.id,
            ],
            shownActionIds: [
              for (final a in eligible)
                if (a.needs.contains(n.need) && shownIds.contains(a.id)) a.id,
            ],
            laterActionIds: [
              for (final a in later)
                if (a.needs.contains(n.need)) a.id,
            ],
            moreBudgetActionIds: [
              for (final a in moreBudget)
                if (a.needs.contains(n.need)) a.id,
            ],
            remedyPlantIds: [
              for (final p in plants)
                if (_linkNeeds(bird!.id, p.plant.id).contains(n.need))
                  p.plant.id,
            ],
          ),
      ],
      actions: shown,
      plants: plants,
      plantsHiddenByFilters: _countHidden(q),
    );
  }

  // --- actions ------------------------------------------------------------

  /// Fixed order, used for tie-breaks and for the remedy lists: free before
  /// low, then higher priority, then a narrower season window (the chance
  /// passes sooner), then id so ties are stable.
  static int _staticOrder(HabitatAction a, HabitatAction b) {
    final cost = a.costTier.index.compareTo(b.costTier.index); // free < low
    if (cost != 0) return cost;
    final pri = b.priority.compareTo(a.priority);
    if (pri != 0) return pri;
    final window = a.months.length.compareTo(b.months.length);
    if (window != 0) return window;
    return a.id.compareTo(b.id);
  }

  /// How much a signature ("featured") action is preferred for its birds:
  /// worth two extra needs covered.
  static const int featuredBonus = 2;

  /// Picks up to [maxActions] from [eligible] (already in [_staticOrder]).
  ///
  /// Slot 1 is the best FREE action when one exists: the guaranteed "free
  /// first step". Each pick is the action that covers the most of the bird's
  /// needs not yet covered by earlier picks, counting [featuredBonus] extra
  /// for an action featured for this bird; ties go to the fixed order.
  ///
  /// After slot 1, an action is only shown if it covers a need not yet
  /// covered. That keeps the list from padding itself with a second action for
  /// the same need ("add water" then "scrub the birdbath"), so fewer than
  /// three may be shown.
  List<HabitatAction> _select(
    List<HabitatAction> eligible,
    Set<Need> target,
    String? birdId,
  ) {
    final remaining = [...eligible];
    final chosen = <HabitatAction>[];
    final covered = <Need>{};

    int newNeeds(HabitatAction a) =>
        a.needs.where((n) => target.contains(n) && !covered.contains(n)).length;

    while (chosen.length < maxActions && remaining.isNotEmpty) {
      var pool = remaining;
      if (chosen.isEmpty) {
        final free =
            remaining.where((a) => a.costTier == CostTier.free).toList();
        if (free.isNotEmpty) pool = free;
      } else {
        pool = remaining.where((a) => newNeeds(a) > 0).toList();
        if (pool.isEmpty) break;
      }

      HabitatAction? best;
      var bestScore = -1;
      for (final a in pool) {
        final featured =
            birdId != null && a.featuredForBirdIds.contains(birdId);
        final score = newNeeds(a) + (featured ? featuredBonus : 0);
        if (score > bestScore) {
          best = a;
          bestScore = score;
        }
      }
      chosen.add(best!);
      remaining.remove(best);
      covered.addAll(best.needs.where(target.contains));
    }
    return chosen;
  }

  // --- plants -------------------------------------------------------------

  bool _plantFits(HabitatQuery q, Plant p) =>
      q.budget.allowsPlants &&
      p.sun.contains(q.sun) &&
      p.spaces.contains(q.space);

  List<Need> _linkNeeds(String birdId, String plantId) {
    for (final l in _repo.links) {
      if (l.birdId == birdId && l.plantId == plantId) return l.needs;
    }
    return const [];
  }

  /// Journal birds (other than the one being asked about) a plant supports.
  List<String> _alsoHelps(HabitatQuery q, String plantId) {
    final out = <String>{};
    for (final l in _repo.links) {
      if (l.plantId == plantId &&
          q.journalBirdIds.contains(l.birdId) &&
          l.birdId != q.birdId) {
        out.add(l.birdId);
      }
    }
    return out.toList()..sort();
  }

  /// Eligible plants, best first.
  ///
  /// Known bird: score = 10 x the link weight (3 = a main reason to plant it)
  /// + how many journal birds it also helps, so weight dominates and the
  /// journal breaks ties. Unknown bird: score = the plant's total weight over
  /// all birds (breadth) + the journal term.
  List<RankedPlant> _rankPlants(HabitatQuery q) {
    final out = <RankedPlant>[];

    if (q.birdId != null) {
      for (final l in _repo.linksForBird(q.birdId!)) {
        final plant = _repo.plantById(l.plantId);
        if (plant == null || !_plantFits(q, plant)) continue;
        final also = _alsoHelps(q, plant.id);
        out.add(RankedPlant(
          plant: plant,
          score: 10 * l.weight + also.length,
          reason: l.reason,
          alsoHelps: also,
        ));
      }
    } else {
      final breadth = <String, int>{};
      for (final l in _repo.links) {
        breadth[l.plantId] = (breadth[l.plantId] ?? 0) + l.weight;
      }
      for (final e in breadth.entries) {
        final plant = _repo.plantById(e.key);
        if (plant == null || !_plantFits(q, plant)) continue;
        final also = _alsoHelps(q, plant.id);
        out.add(RankedPlant(
          plant: plant,
          score: e.value + also.length,
          alsoHelps: also,
        ));
      }
    }

    out.sort((a, b) {
      final s = b.score.compareTo(a.score);
      return s != 0 ? s : a.plant.id.compareTo(b.plant.id);
    });
    return out;
  }

  int _countHidden(HabitatQuery q) {
    final linked = q.birdId != null
        ? _repo.linksForBird(q.birdId!).map((l) => l.plantId).toSet()
        : _repo.links.map((l) => l.plantId).toSet();
    var hidden = 0;
    for (final id in linked) {
      final plant = _repo.plantById(id);
      if (plant != null && !_plantFits(q, plant)) hidden++;
    }
    return hidden;
  }
}
