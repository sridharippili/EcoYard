import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';

import '../../app/content.dart';
import 'plant_detail_screen.dart';
import 'species_photo.dart';
import 'plant_finder_controller.dart';
import '../../app/filter_menus.dart';
import '../../app/surfaces.dart';
import '../weather/place_picker.dart';
import '../weather/weather_controller.dart';
import 'plant_labels.dart';

/// The Plants tab: native plants that fit the user's space, sun and budget.
class PlantFinderScreen extends StatelessWidget {
  const PlantFinderScreen({
    super.key,
    required this.controller,
    required this.content,
    this.weather,
  });

  final PlantFinderController controller;
  final AppContent content;

  /// Holds the town the user chose, and opens the picker to change it.
  final WeatherController? weather;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, ?weather]),
      builder: (context, _) {
        final text = Theme.of(context).textTheme;
        final r = controller.result;
        final repo = content.repo;
        final draft = content.isDraft;
        return ListView(
          padding: tabListPadding(context),
          children: [
            Text(
              'Native Plants',
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const SizedBox(height: 8),
            _LocationRow(region: regionLabel(repo.region), weather: weather),
            const SizedBox(height: 12),
            _Filters(controller: controller),
            const SizedBox(height: 12),
            if (controller.freeFirstStep != null)
              _FreeStep(action: controller.freeFirstStep!),
            const SizedBox(height: 8),
            if (r.plants.isEmpty)
              _EmptyState(controller: controller)
            else ...[
              Text(
                '${r.plants.length} ${r.plants.length == 1 ? 'plant fits' : 'plants fit'}',
                style: text.titleSmall,
              ),
              const SizedBox(height: 4),
              for (final p in r.plants)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _PlantCard(
                    plant: p,
                    photo: content.photos.forPlant(p.plant.id),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PlantDetailScreen(
                          plant: p,
                          content: content,
                          draft: draft,
                        ),
                      ),
                    ),
                  ),
                ),
              if (r.hiddenCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${r.hiddenCount} more ${r.hiddenCount == 1 ? 'plant doesn\'t' : 'plants don\'t'} '
                    'fit these choices. Change the space, sun or budget to '
                    'see them.',
                    style: text.bodySmall,
                  ),
                ),
            ],
            const SizedBox(height: 16),
            Text(
              draft
                  ? 'Northeast US native plant list. Draft content, not yet '
                        'reviewed. No sponsored plants.'
                  : 'Northeast US native plant list. No sponsored plants.',
              style: text.bodySmall,
            ),
          ],
        );
      },
    );
  }
}

/// Where the plants are for: a bordered row with the town (or the region) and
/// a Change action, like the mockup. The list itself is for the whole region;
/// the town is the user's own place, shared with the weather card.
class _LocationRow extends StatelessWidget {
  const _LocationRow({required this.region, required this.weather});
  final String region;
  final WeatherController? weather;

  @override
  Widget build(BuildContext context) {
    final t = context.eco;
    final place = weather?.place;
    final w = weather;
    return InteractiveSurface(
      chevron: false,
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      onTap: w == null ? null : () => showPlacePicker(context, w),
      child: Row(
        children: [
          Icon(Icons.place_outlined, color: t.accentText),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  place == null ? region : '${place.label} (approximate)',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (place != null)
                  Text(
                    'Plants for $region',
                    style: TextStyle(fontSize: 12, color: t.textSecondary),
                  ),
              ],
            ),
          ),
          if (w != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Change',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: t.accentText,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.controller});
  final PlantFinderController controller;

  @override
  Widget build(BuildContext context) {
    return FilterMenuRow(
      menus: [
        FilterMenu<SpaceType>(
          key: filterSpaceKey,
          label: 'My space',
          value: controller.space,
          options: [for (final s in SpaceType.values) (s, spaceLabel(s))],
          onChanged: controller.setSpace,
        ),
        FilterMenu<SunExposure>(
          key: filterSunKey,
          label: 'Sunlight',
          value: controller.sun,
          options: [for (final s in SunExposure.values) (s, sunLabel(s))],
          onChanged: controller.setSun,
        ),
        FilterMenu<BudgetTier>(
          key: filterBudgetKey,
          label: 'Budget',
          value: controller.budget,
          options: const [
            (BudgetTier.low, 'Low cost'),
            (BudgetTier.free, 'Free only'),
            (BudgetTier.any, 'Any'),
          ],
          onChanged: controller.setBudget,
        ),
      ],
    );
  }
}

class _FreeStep extends StatelessWidget {
  const _FreeStep({required this.action});
  final HabitatAction action;

  @override
  Widget build(BuildContext context) => InfoSurface(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Free first step: ${action.title}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        Text(action.body),
      ],
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.controller});
  final PlantFinderController controller;

  @override
  Widget build(BuildContext context) {
    final r = controller.result;
    final String message;
    if (controller.budget == BudgetTier.free && r.noPlantIsFree) {
      message =
          'No plant in this list is free. Plants cost a little, so try '
          '"Low cost" or "Any" to see them. The free first step above works '
          'without buying anything.';
    } else {
      message =
          'No plant in our list fits this space and sun'
          '${controller.budget == BudgetTier.free ? ' for free' : ''}. '
          'Try another space or amount of sun.';
    }
    final fix = controller.suggestRelaxation();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message),
          if (fix != null) ...[
            const SizedBox(height: 8),
            FilledButton.tonal(onPressed: fix.apply, child: Text(fix.label)),
          ],
        ],
      ),
    );
  }
}

class _PlantCard extends StatelessWidget {
  const _PlantCard({
    required this.plant,
    required this.photo,
    required this.onTap,
  });
  final FinderPlant plant;
  final PhotoCredit? photo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = plant.plant;
    // Two badges at most, by priority: where it is native, then what it costs.
    final tags = [nativityBadge(p.nativity), plantCostLabel(p.costTier)];
    // Tappable: an interactive surface (raised, bordered, with a chevron).
    return InteractiveSurface(
      onTap: onTap,
      chevron: false,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SpeciesPhoto(credit: photo, width: 64, height: 64),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.commonName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    Text(supportLine(plant)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Icon(
                  Icons.chevron_right,
                  color: context.eco.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Full card width, so the two badges stay on one line.
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [for (final t in tags) _Tag(t, cost: p.costTier)],
          ),
        ],
      ),
    );
  }
}

/// A small read-only pill. The cost one uses the Free / Low cost badge
/// colours; the others are neutral.
class _Tag extends StatelessWidget {
  const _Tag(this.text, {required this.cost});
  final String text;
  final CostTier cost;
  @override
  Widget build(BuildContext context) {
    final t = context.eco;
    final isCost = text == plantCostLabel(cost);
    final free = cost == CostTier.free;
    return InfoPill(
      label: text,
      background: isCost
          ? (free ? t.badgeFree : t.badgeLowCost)
          : t.surfaceInfo,
      foreground: isCost
          ? (free ? t.badgeFreeOn : t.badgeLowCostOn)
          : t.textSecondary,
    );
  }
}

/// Photo stand-in for the detail screen, when a plant has no credited photo.
class PlantPhotoPlaceholder extends StatelessWidget {
  const PlantPhotoPlaceholder({super.key, this.credit});

  final PhotoCredit? credit;

  @override
  Widget build(BuildContext context) => credit == null
      ? SpeciesPhoto(
          credit: null,
          width: double.infinity,
          height: 180,
          radius: 16,
          placeholderLabel: 'Photo coming soon',
        )
      : SpeciesPhoto.hero(credit: credit, radius: 16);
}
