import 'models.dart';
import 'reference_repository.dart';

/// One action in the user's plan, as stored. Plain data: ids and ISO-8601
/// text only, so any storage can hold it.
///
/// The title, body and cost are a SNAPSHOT of what the user saw when they
/// added the action. Content is rewritten between releases; the snapshot keeps
/// a saved plan readable when an action is reworded or removed.
class PlanEntry {
  const PlanEntry({
    required this.actionId,
    required this.birdIds,
    required this.addedOn,
    required this.titleSnapshot,
    required this.bodySnapshot,
    required this.costSnapshot,
    this.doneOn,
  });

  final String actionId;

  /// Every bird this action was added for. One action, many birds.
  final List<String> birdIds;

  /// UTC, ISO-8601.
  final String addedOn;

  /// UTC, ISO-8601. Null while the action is still to do.
  final String? doneOn;

  final String titleSnapshot;
  final String bodySnapshot;

  /// [CostTier.json] at the time of adding.
  final String costSnapshot;

  bool get isDone => doneOn != null;
}

/// An action the user wants added to the plan (before it is stored).
class PlanCandidate {
  const PlanCandidate({
    required this.actionId,
    required this.title,
    required this.body,
    required this.costTier,
  });

  factory PlanCandidate.fromAction(HabitatAction a) => PlanCandidate(
        actionId: a.id,
        title: a.title,
        body: a.body,
        costTier: a.costTier,
      );

  final String actionId;
  final String title;
  final String body;
  final CostTier costTier;
}

/// What adding to the plan changed, so the banner can be truthful.
class PlanAddResult {
  const PlanAddResult({
    required this.added,
    required this.alreadyInPlan,
  });

  /// Actions that were not in the plan before.
  final List<String> added;

  /// Actions already in the plan. Only the bird was added to them.
  final List<String> alreadyInPlan;
}

/// A [PlanEntry] joined with the current content for display.
class PlanItem {
  const PlanItem({
    required this.entry,
    required this.action,
    required this.birds,
    required this.unknownBirdCount,
  });

  final PlanEntry entry;

  /// The action as it is in the content today. Null when the content no
  /// longer has it: the item then shows its snapshot and can be removed.
  final HabitatAction? action;

  /// Birds still in the content, in the order they were added.
  final List<Bird> birds;

  /// Birds saved in the plan that the content no longer has.
  final int unknownBirdCount;

  bool get isRemovedFromContent => action == null;
  bool get isDone => entry.isDone;

  String get title => action?.title ?? entry.titleSnapshot;
  String get body => action?.body ?? entry.bodySnapshot;
  String get costJson => action?.costTier.json ?? entry.costSnapshot;
}

class PlanProgress {
  const PlanProgress({required this.done, required this.total});
  final int done;
  final int total;
  double get fraction => total == 0 ? 0 : done / total;
}

/// The plan as the screen shows it.
class PlanView {
  const PlanView({required this.items, required this.progress});

  /// To-do first, done last. Inside each group: oldest added first, then id,
  /// so ticking an item never reshuffles the others.
  final List<PlanItem> items;

  /// Counts every stored item, including ones removed from the content, so
  /// nothing the user can see is left out of the count.
  final PlanProgress progress;
}

/// Orders stored entries for display and joins them with the content.
/// Pure: the same entries and content always give the same view.
PlanView buildPlanView(List<PlanEntry> entries, ReferenceRepository repo) {
  // Compare as times, not as text: ISO strings of different precision do not
  // sort correctly as text. Unparseable text falls back to text order.
  int byAdded(PlanEntry a, PlanEntry b) {
    final ta = DateTime.tryParse(a.addedOn);
    final tb = DateTime.tryParse(b.addedOn);
    final c = (ta != null && tb != null)
        ? ta.compareTo(tb)
        : a.addedOn.compareTo(b.addedOn);
    return c != 0 ? c : a.actionId.compareTo(b.actionId);
  }

  final sorted = [...entries]..sort(byAdded);
  final ordered = [
    ...sorted.where((e) => !e.isDone),
    ...sorted.where((e) => e.isDone),
  ];
  final items = [
    for (final e in ordered)
      () {
        final birds = <Bird>[];
        var unknown = 0;
        for (final id in e.birdIds) {
          final b = repo.birdById(id);
          if (b == null) {
            unknown++;
          } else {
            birds.add(b);
          }
        }
        return PlanItem(
          entry: e,
          action: repo.actionById(e.actionId),
          birds: birds,
          unknownBirdCount: unknown,
        );
      }(),
  ];
  return PlanView(
    items: items,
    progress: PlanProgress(
      done: entries.where((e) => e.isDone).length,
      total: entries.length,
    ),
  );
}
