import 'package:bird_audio/bird_audio.dart';
import 'package:bird_audio/bird_audio.dart' show Detection;
import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/content.dart';
import '../../app/filter_menus.dart';
import '../../app/surfaces.dart';
import '../../app/theme.dart';
import '../plan/plan_controller.dart';

String needLabel(Need n) => switch (n) {
  Need.food => 'Food',
  Need.shelter => 'Shelter',
  Need.water => 'Water',
  Need.nesting => 'Nesting',
  Need.safety => 'Safety',
};

IconData needIcon(Need n) => switch (n) {
  Need.food => Icons.restaurant_outlined,
  Need.shelter => Icons.park_outlined,
  Need.water => Icons.water_drop_outlined,
  Need.nesting => Icons.home_outlined,
  Need.safety => Icons.shield_outlined,
};

/// The icon chip's background and icon colour for a need, for each theme.
(Color, Color) needChipColors(Need n, Brightness b) {
  final dark = b == Brightness.dark;
  return switch (n) {
    Need.food =>
      dark
          ? (const Color(0xFF3A2A1E), const Color(0xFFFFB98A))
          : (const Color(0xFFFDE8DC), const Color(0xFF9A4A1E)),
    Need.shelter =>
      dark
          ? (const Color(0xFF1E3A2B), const Color(0xFFA9E3BF))
          : (const Color(0xFFDDEFE2), const Color(0xFF1F5C3F)),
    Need.water =>
      dark
          ? (const Color(0xFF1B2E44), const Color(0xFF9CC8F5))
          : (const Color(0xFFDDEBF8), const Color(0xFF1D5C9A)),
    Need.nesting =>
      dark
          ? (const Color(0xFF3A3220), const Color(0xFFE0C98A))
          : (const Color(0xFFEFE6D6), const Color(0xFF6B5428)),
    Need.safety =>
      dark
          ? (const Color(0xFF47294D), const Color(0xFFE0AEEA))
          : (const Color(0xFFF1E1F3), const Color(0xFF7A3A86)),
  };
}

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
    void toggle(String id, bool on) => setState(() {
      final next = {...checked};
      on ? next.add(id) : next.remove(id);
      _checked = next;
    });

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
          for (final n in rec.supportNeeds)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _NeedRow(need: n, repo: repo),
            ),
          const SizedBox(height: 8),
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
          // Read-only advice with ticks: one tinted card, the ticks are its
          // only controls.
          InfoSurface(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
            child: Column(
              children: [
                for (final a in rec.actions)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _saving
                        ? null
                        : () => toggle(a.id, !checked.contains(a.id)),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: checked.contains(a.id),
                          onChanged: _saving
                              ? null
                              : (v) => toggle(a.id, v == true),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  a.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  a.body,
                                  style: TextStyle(
                                    color: context.eco.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                _CostTag(a.costTier.json),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
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
        // A bird we have no content for can still add the general actions,
        // as long as the service gave it a name.
        if (rec.actions.isNotEmpty &&
            (bird != null || m.displayName.trim().isNotEmpty)) ...[
          const SizedBox(height: 12),
          PrimaryAction(
            label: selected.isEmpty
                ? 'Add these to my plan'
                : 'Add ${selected.length} to my plan',
            icon: Icons.add,
            onPressed: selected.isEmpty || _saving
                ? null
                : () => _addToPlan(bird, m.displayName, selected),
          ),
        ],
        const SizedBox(height: 16),
        _PlantsSection(rec: rec, bird: bird),
      ],
    );
  }

  Future<void> _addToPlan(
    Bird? bird,
    String name,
    List<HabitatAction> actions,
  ) async {
    // A second tap in the same frame arrives before the button is disabled.
    if (_saving) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final candidates = [for (final a in actions) PlanCandidate.fromAction(a)];
      if (bird != null) {
        await widget.plan.add(bird: bird, actions: candidates);
      } else {
        await widget.plan.addForOtherBird(name: name, actions: candidates);
      }
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
  Widget build(BuildContext context) => CostBadge(free: costJson == 'free');
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            'For this suggestion',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
        FilterMenuRow(
          menus: [
            FilterMenu<SpaceType>(
              key: filterSpaceKey,
              label: 'Space',
              value: space,
              options: const [
                (SpaceType.yard, 'Yard'),
                (SpaceType.balcony, 'Balcony'),
                (SpaceType.containers, 'Containers'),
              ],
              onChanged: (v) => onChanged(v, sun, budget),
            ),
            FilterMenu<SunExposure>(
              key: filterSunKey,
              label: 'Sun',
              value: sun,
              options: const [
                (SunExposure.full, 'Full'),
                (SunExposure.partial, 'Partial'),
                (SunExposure.shade, 'Shade'),
              ],
              onChanged: (v) => onChanged(space, v, budget),
            ),
            FilterMenu<BudgetTier>(
              key: filterBudgetKey,
              label: 'Budget',
              value: budget,
              options: const [
                (BudgetTier.free, 'Free only'),
                (BudgetTier.low, 'Free + low cost'),
              ],
              onChanged: (v) => onChanged(space, sun, v),
            ),
          ],
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
  Widget build(BuildContext context) {
    final (bg, fg) = needChipColors(need.need, Theme.of(context).brightness);
    // A bordered row on the page with a coloured icon chip. It is not
    // tappable, so no chevron and no pressed state.
    return InteractiveSurface(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(needIcon(need.need), color: fg),
          ),
          const SizedBox(width: 12),
          Expanded(
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
          ),
        ],
      ),
    );
  }
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
