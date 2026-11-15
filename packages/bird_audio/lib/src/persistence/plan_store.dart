import 'package:ecoyard_core/ecoyard_core.dart';

/// Where the user's habitat plan is kept. Screens depend on this, never on
/// SQLite, so tests use [InMemoryPlanStore].
///
/// All times are passed in (never read from the clock here) and stored as UTC
/// ISO-8601 text.
abstract interface class PlanStore {
  /// Every action in the plan. Order is not meaningful: use `buildPlanView`.
  Future<List<PlanEntry>> load();

  /// Adds [actions] for [birdId], in one transaction: either every action is
  /// stored or none is.
  ///
  /// - An action not yet in the plan is added with its snapshot.
  /// - An action already in the plan keeps its `addedOn`, its done state and
  ///   its snapshot; only the bird is added to it (once).
  Future<PlanAddResult> add({
    required String birdId,
    required List<PlanCandidate> actions,
    required DateTime now,
  });

  /// Ticks or un-ticks an action. Unknown ids are ignored.
  Future<void> setDone(
    String actionId, {
    required bool done,
    required DateTime now,
  });

  /// Removes one action (and its birds) from the plan.
  Future<void> remove(String actionId);

  /// Deletes the whole plan. For the future "delete my data" screen.
  Future<void> clear();

  Future<void> close();
}

/// [actions] without repeats (first one wins), keeping their order.
List<PlanCandidate> uniqueCandidates(List<PlanCandidate> actions) {
  final seen = <String>{};
  return [
    for (final a in actions)
      if (seen.add(a.actionId)) a,
  ];
}

/// The stored timestamp for the [index]th action of one add: [now] plus
/// [index] milliseconds, as UTC ISO-8601 with exactly three fractional digits.
///
/// Fixed width on purpose: ISO strings of different precision do not sort as
/// text (`.000Z` sorts after `.000001Z`). The index keeps the order the
/// actions were chosen in.
String stampFor(DateTime now, [int index = 0]) =>
    DateTime.fromMillisecondsSinceEpoch(
      now.millisecondsSinceEpoch + index,
      isUtc: true,
    ).toIso8601String();

/// A [PlanStore] in memory, for tests and previews. Same rules as SQLite.
class InMemoryPlanStore implements PlanStore {
  final Map<String, PlanEntry> _entries = {};

  /// Set to make the next call fail, to test error states.
  Object? failNext;

  void _maybeFail() {
    final f = failNext;
    if (f != null) {
      failNext = null;
      throw f;
    }
  }

  @override
  Future<List<PlanEntry>> load() async {
    _maybeFail();
    return _entries.values.toList();
  }

  @override
  Future<PlanAddResult> add({
    required String birdId,
    required List<PlanCandidate> actions,
    required DateTime now,
  }) async {
    _maybeFail();
    final added = <String>[];
    final already = <String>[];
    final next = {..._entries};
    final unique = uniqueCandidates(actions);
    for (var i = 0; i < unique.length; i++) {
      final a = unique[i];
      final old = next[a.actionId];
      if (old == null) {
        next[a.actionId] = PlanEntry(
          actionId: a.actionId,
          birdIds: [birdId],
          addedOn: stampFor(now, i),
          titleSnapshot: a.title,
          bodySnapshot: a.body,
          costSnapshot: a.costTier.json,
        );
        added.add(a.actionId);
      } else {
        already.add(a.actionId);
        if (!old.birdIds.contains(birdId)) {
          next[a.actionId] = PlanEntry(
            actionId: old.actionId,
            birdIds: [...old.birdIds, birdId],
            addedOn: old.addedOn,
            doneOn: old.doneOn,
            titleSnapshot: old.titleSnapshot,
            bodySnapshot: old.bodySnapshot,
            costSnapshot: old.costSnapshot,
          );
        }
      }
    }
    _entries
      ..clear()
      ..addAll(next);
    return PlanAddResult(added: added, alreadyInPlan: already);
  }

  @override
  Future<void> setDone(
    String actionId, {
    required bool done,
    required DateTime now,
  }) async {
    _maybeFail();
    final old = _entries[actionId];
    if (old == null) return;
    _entries[actionId] = PlanEntry(
      actionId: old.actionId,
      birdIds: old.birdIds,
      addedOn: old.addedOn,
      doneOn: done ? stampFor(now) : null,
      titleSnapshot: old.titleSnapshot,
      bodySnapshot: old.bodySnapshot,
      costSnapshot: old.costSnapshot,
    );
  }

  @override
  Future<void> remove(String actionId) async {
    _maybeFail();
    _entries.remove(actionId);
  }

  @override
  Future<void> clear() async {
    _maybeFail();
    _entries.clear();
  }

  @override
  Future<void> close() async {}
}
