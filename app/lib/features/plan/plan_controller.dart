import 'dart:async';

import 'package:bird_audio/bird_audio.dart';
import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:flutter/foundation.dart';

enum PlanLoadState { loading, ready, failed }

/// State of the My Plan tab, shared with the Bird Details panel so that
/// "Add these to my plan" and the plan list never disagree.
class PlanController extends ChangeNotifier {
  PlanController({
    required this.repo,
    required this.openStore,
    required this.now,
  });

  final ReferenceRepository repo;
  final Future<PlanStore> Function() openStore;
  final DateTime Function() now;

  PlanLoadState state = PlanLoadState.loading;
  PlanView? view;

  /// Set when something the user did (tick, remove) could not be saved.
  String? actionError;

  /// Shown at the top of My Plan right after adding; null otherwise.
  String? banner;

  PlanStore? _store;
  bool _disposed = false;
  Future<void>? _starting;
  final Set<Future<void>> _inFlight = {};

  /// Opens the database and loads the plan. Safe to call again to retry, and
  /// safe to call twice at once: the second call joins the first, so only one
  /// database handle is ever opened.
  /// On failure the plan is NOT shown as empty: [state] is `failed`.
  Future<void> init() =>
      _starting ??= _init().whenComplete(() => _starting = null);

  Future<void> _init() async {
    state = PlanLoadState.loading;
    _notify();
    try {
      final store = _store ?? await openStore();
      if (_disposed) {
        unawaited(store.close());
        return;
      }
      _store = store;
      await _reload();
      state = PlanLoadState.ready;
    } catch (_) {
      state = PlanLoadState.failed;
    }
    _notify();
  }

  Future<void> _reload() async {
    view = buildPlanView(await _store!.load(), repo);
  }

  /// Runs [work] and remembers it, so [dispose] waits for it before closing
  /// the database.
  Future<T> _track<T>(Future<T> Function() work) {
    final f = work();
    final done = f.then<void>((_) {}, onError: (_) {});
    _inFlight.add(done);
    done.whenComplete(() => _inFlight.remove(done));
    return f;
  }

  /// Adds [actions] for [birdId]. Throws when nothing could be saved, so the
  /// caller can keep its checkboxes and not navigate away. If the save worked
  /// but re-reading the plan failed, it still returns normally: the data is
  /// safe and the plan tab shows its own error.
  Future<PlanAddResult> add({
    required Bird bird,
    required List<PlanCandidate> actions,
  }) => _addFor(bird.id, bird.commonName, actions);

  /// Adds the general actions for a bird we have no content for (any species
  /// the identification service names). The plan shows it as "another bird".
  Future<PlanAddResult> addForOtherBird({
    required String name,
    required List<PlanCandidate> actions,
  }) => _addFor(otherBirdId(name), name, actions);

  /// A stable id for a bird we have no content for, from its name.
  static String otherBirdId(String name) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return 'other-${slug.isEmpty ? 'bird' : slug}';
  }

  Future<PlanAddResult> _addFor(
    String birdId,
    String label,
    List<PlanCandidate> actions,
  ) => _track(() async {
    if (_store == null) {
      await init();
      if (_store == null) throw StateError('The plan could not be opened.');
    }
    final result = await _store!.add(
      birdId: birdId,
      actions: actions,
      now: now(),
    );
    banner = _bannerText(label, result);
    actionError = null;
    try {
      await _reload();
      state = PlanLoadState.ready;
    } catch (_) {
      state = PlanLoadState.failed;
    }
    _notify();
    return result;
  });

  static String _bannerText(String bird, PlanAddResult r) {
    final n = r.added.length;
    final m = r.alreadyInPlan.length;
    if (n == 0) {
      return m == 1
          ? 'That action was already in your plan. '
                '$bird was added to it.'
          : 'Those actions were already in your plan. '
                '$bird was added to them.';
    }
    final head = '$n ${n == 1 ? 'action' : 'actions'} added for $bird';
    return m == 0 ? head : '$head · $m already in your plan';
  }

  void dismissBanner() {
    banner = null;
    _notify();
  }

  Future<void> setDone(String actionId, bool done) async {
    await _change(() => _store!.setDone(actionId, done: done, now: now()));
  }

  Future<void> remove(String actionId) async {
    await _change(() => _store!.remove(actionId));
  }

  Future<void> _change(Future<void> Function() write) => _track(() async {
    banner = null;
    try {
      await write();
      actionError = null;
    } catch (_) {
      actionError = 'That change could not be saved. Please try again.';
    }
    try {
      await _reload();
    } catch (_) {
      state = PlanLoadState.failed;
    }
    _notify();
  });

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    // Let a save that is still running finish before closing the database.
    final pending = [..._inFlight];
    unawaited(
      Future.wait(pending).whenComplete(() async {
        try {
          await _store?.close();
        } catch (_) {}
      }),
    );
    super.dispose();
  }
}
