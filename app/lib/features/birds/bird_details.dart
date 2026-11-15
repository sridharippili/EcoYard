import 'package:bird_audio/bird_audio.dart';
import 'package:bird_audio/bird_audio.dart' show Detection;
import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/content.dart';
import '../plan/plan_controller.dart';

String needLabel(Need n) => switch (n) {
  Need.food => 'Food',
  Need.shelter => 'Shelter',
  Need.water => 'Water',
  Need.nesting => 'Nesting',
  Need.safety => 'Safety',
};

String costLabel(String costJson) => costJson == 'free' ? 'Free' : 'Low cost';

/// Habitat advice for one identified sound: what the bird needs, what to do
/// about it, and which plants help. Sits under the result card on the Birds
/// tab.
///
/// Copy rules (CLAUDE.md rule 7): says nothing about where audio is kept; the
/// privacy badge above it names the service that answered.
class BirdDetailsPanel extends StatefulWidget {
  const BirdDetailsPanel({
    super.key,
    required this.detection,
    required this.content,
    required this.plan,
    required this.settings,
    required this.now,
    required this.onOpenPlan,
  });

  final Detection detection;
  final AppContent content;
  final PlanController plan;

  /// Starting choices, taken when this panel is created.
  final AppSettings settings;
  final DateTime Function() now;

  /// Switches to the My Plan tab.
  final VoidCallback onOpenPlan;

  /// The photo for a detection, if we have a credited one. Used by the
  /// result card above the panel, so the picture sits at the top.
  static PhotoCredit? photoFor(AppContent content, Detection d) {
    final m = content.resolver.resolve(
      rawName: d.speciesText,
      scientificName: d.scientificName,
      confidence: d.confidence,
    );
    final id = m.taxonId;
    return id == null ? null : content.photos.forBird(id);
  }

  @override
  State<BirdDetailsPanel> createState() => _BirdDetailsPanelState();
}

class _BirdDetailsPanelState extends State<BirdDetailsPanel> {
  // Session-only answers. They are not saved anywhere (Settings, Phase 6).
  late SpaceType _space = widget.settings.defaultSpace;
  late SunExposure _sun = widget.settings.defaultSun;
  // The advice offers Free only / Free + low cost; "Any" means the latter.
  late BudgetTier _budget = widget.settings.defaultBudget == BudgetTier.free
      ? BudgetTier.free
      : BudgetTier.low;

  // The panel is rebuilt with a new key for each new answer, so this never
  // goes stale.
  late final SpeciesMatch _match = _resolve();

  /// Ids the user left ticked. Null means "all shown actions" (the default
  /// after any change of choices).
  Set<String>? _checked;
  bool _saving = false;
  String? _saveError;

  SpeciesMatch _resolve() => widget.content.resolver.resolve(
    rawName: widget.detection.speciesText,
    scientificName: widget.detection.scientificName,
    confidence: widget.detection.confidence,
  );

  HabitatRecommendation? _recommend() {
    final m = _match;
    if (!m.isBird) return null;
    final provider = m.providerConfidence;
    if (m.isResolved) {
      if (m.confidence == MatchConfidence.low) return null;
    } else if (provider != null && provider < 0.4) {
      return null;
    }
    return widget.content.engine.recommend(
      HabitatQuery(
        birdId: m.taxonId,
        space: _space,
        sun: _sun,
        budget: _budget,
        month: widget.now().month,
        regionCode: widget.content.repo.region,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = _match;
    if (!m.isBird) {
      return const _Message(
        icon: Icons.hearing_disabled_outlined,
        text:
            'That sounded like something other than a bird. '
            'Try again closer to the bird.',
      );
    }
    final rec = _recommend();
    if (rec == null) {
      return const _Message(
        icon: Icons.help_outline,
        text:
            "We couldn't identify this sound well enough to suggest "
            'anything. Try again closer to the bird.',
      );
    }

    final repo = widget.content.repo;
    final bird = m.isResolved ? repo.birdById(m.taxonId!) : null;
    // Every shown action starts checked; changing a choice resets this.
    final checked = _checked ?? rec.actions.map((a) => a.id).toSet();
    final selected = [
      for (final a in rec.actions)
        if (checked.contains(a.id)) a,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (rec.isGeneric)
          _Message(
            icon: Icons.info_outline,
            text:
                "We don't have advice for ${m.displayName} yet. "
                'These things help most birds.',
          ),
        const SizedBox(height: 12),
        _Choices(
          space: _space,
          sun: _sun,
          budget: _budget,
          onChanged: (s, u, b) => setState(() {
            _space = s;
            _sun = u;
            _budget = b;
            _checked = null;
            _saveError = null;
          }),
        ),
        const SizedBox(height: 16),
        if (!rec.isGeneric) ...[
          _Heading('How to support this bird'),
          for (final n in rec.supportNeeds) _NeedRow(need: n, repo: repo),
          const SizedBox(height: 16),
        ],
        _Heading('Simple actions'),
        if (rec.actions.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Nothing fits this month with these choices. '
              'Try a different space or budget above.',
            ),
          )
        else ...[
          for (final a in rec.actions)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: checked.contains(a.id),
              onChanged: _saving
                  ? null
                  : (v) => setState(() {
                      final next = {...checked};
                      v == true ? next.add(a.id) : next.remove(a.id);
                      _checked = next;
                    }),
              title: Text(a.title),
              subtitle: Text(a.body),
              secondary: _CostTag(a.costTier.json),
            ),
          if (rec.actions.length < 3)
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text(
                'Nothing else adds to this right now.',
                style: TextStyle(fontSize: 12),
              ),
            ),
        ],
        if (_saveError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _saveError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (bird != null && rec.actions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FilledButton(
              onPressed: selected.isEmpty || _saving
                  ? null
                  : () => _addToPlan(bird, selected),
              child: Text(
                selected.isEmpty
                    ? 'Add these to my plan'
                    : 'Add ${selected.length} to my plan',
              ),
            ),
          ),
        const SizedBox(height: 16),
        _PlantsSection(rec: rec, bird: bird),
      ],
    );
  }

  Future<void> _addToPlan(Bird bird, List<HabitatAction> actions) async {
    // A second tap in the same frame arrives before the button is disabled.
    if (_saving) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.plan.add(
        bird: bird,
        actions: [for (final a in actions) PlanCandidate.fromAction(a)],
      );
    } catch (_) {
      if (!mounted) return;
      // Stay here with the boxes as they were.
      setState(() {
        _saving = false;
        _saveError = "Couldn't save to your plan. Please try again.";
      });
      return;
    }
    if (!mounted) return;
    // Stays "saving" on purpose: the panel is about to be replaced, and a tap
    // in the meantime must not add a second time.
    widget.onOpenPlan();
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _CostTag extends StatelessWidget {
  const _CostTag(this.costJson);
  final String costJson;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(costLabel(costJson), style: const TextStyle(fontSize: 11)),
  );
}

class _Choices extends StatelessWidget {
  const _Choices({
    required this.space,
    required this.sun,
    required this.budget,
    required this.onChanged,
  });

  final SpaceType space;
  final SunExposure sun;
  final BudgetTier budget;
  final void Function(SpaceType, SunExposure, BudgetTier) onChanged;

  @override
  Widget build(BuildContext context) {
    Widget row<T>(
      String label,
      List<(T, String)> options,
      T value,
      void Function(T) set,
    ) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Wrap(
        spacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(width: 58, child: Text(label)),
          for (final (v, text) in options)
            ChoiceChip(
              label: Text(text),
              selected: v == value,
              showCheckmark: true,
              onSelected: (_) => set(v),
            ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'For this suggestion',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        row<SpaceType>(
          'Space',
          const [
            (SpaceType.yard, 'Yard'),
            (SpaceType.balcony, 'Balcony'),
            (SpaceType.containers, 'Containers'),
          ],
          space,
          (v) => onChanged(v, sun, budget),
        ),
        row<SunExposure>(
          'Sun',
          const [
            (SunExposure.full, 'Full'),
            (SunExposure.partial, 'Partial'),
            (SunExposure.shade, 'Shade'),
          ],
          sun,
          (v) => onChanged(space, v, budget),
        ),
        row<BudgetTier>(
          'Budget',
          const [
            (BudgetTier.free, 'Free only'),
            (BudgetTier.low, 'Free + low cost'),
          ],
          budget,
          (v) => onChanged(space, sun, v),
        ),
      ],
    );
  }
}

class _NeedRow extends StatelessWidget {
  const _NeedRow({required this.need, required this.repo});
  final NeedCoverage need;
  final ReferenceRepository repo;

  String _titles(List<String> ids) => ids
      .map((id) => repo.actionById(id)?.title)
      .whereType<String>()
      .join(', ');

  /// What can be done about this need, in words. Never claims nothing can
  /// help when an out-of-season or budget-blocked action exists.
  String get _status {
    if (need.coveredByShownActions) {
      return 'Covered by: ${_titles(need.shownActionIds)}';
    }
    if (need.hasRemedy) {
      if (need.remedyActionIds.isNotEmpty) {
        return 'Also possible: ${_titles(need.remedyActionIds)}';
      }
      return 'Helped by the plants below.';
    }
    if (need.laterActionIds.isNotEmpty) {
      return 'Nothing to do this month. Later in the year: '
          '${_titles(need.laterActionIds)}';
    }
    if (need.moreBudgetActionIds.isNotEmpty) {
      return 'A small budget would unlock: '
          '${_titles(need.moreBudgetActionIds)}';
    }
    return 'Nothing to do for this right now.';
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          needLabel(need.need),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Text(need.why),
        Text(_status, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

class _PlantsSection extends StatelessWidget {
  const _PlantsSection({required this.rec, required this.bird});

  final HabitatRecommendation rec;
  final Bird? bird;

  @override
  Widget build(BuildContext context) {
    final shown = rec.plants.take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading(
          bird == null
              ? 'Native plants for birds'
              : 'Native plants for ${bird!.commonName}',
        ),
        if (shown.isEmpty)
          const Text('No plant in our list fits this sun, space and budget.')
        else
          for (final p in shown)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(p.plant.commonName),
              subtitle: Text(p.reason ?? p.plant.scientificName),
            ),
        if (rec.plantsHiddenByFilters > 0)
          Text(
            '${rec.plantsHiddenByFilters} more would help but need different '
            'sun, space or budget.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}
