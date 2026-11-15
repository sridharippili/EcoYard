import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';

import '../../app/content.dart';
import 'plant_detail_screen.dart';
import 'species_photo.dart';
import 'plant_finder_controller.dart';
import 'plant_labels.dart';

/// The Plants tab: native plants that fit the user's space, sun and budget.
class PlantFinderScreen extends StatelessWidget {
  const PlantFinderScreen({
    super.key,
    required this.controller,
    required this.content,
  });

  final PlantFinderController controller;
  final AppContent content;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
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
            Row(
              children: [
                const Icon(Icons.place_outlined, size: 16),
                const SizedBox(width: 4),
                Expanded(child: Text(regionLabel(repo.region))),
              ],
            ),
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
                _PlantCard(
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

class _Filters extends StatelessWidget {
  const _Filters({required this.controller});
  final PlantFinderController controller;

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
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 72),
            child: Text(label),
          ),
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
        row<SpaceType>(
          'My space',
          [for (final s in SpaceType.values) (s, spaceLabel(s))],
          controller.space,
          controller.setSpace,
        ),
        row<SunExposure>(
          'Sunlight',
          [for (final s in SunExposure.values) (s, sunLabel(s))],
          controller.sun,
          controller.setSun,
        ),
        row<BudgetTier>(
          'Budget',
          const [
            (BudgetTier.low, 'Low cost'),
            (BudgetTier.free, 'Free only'),
            (BudgetTier.any, 'Any'),
          ],
          controller.budget,
          controller.setBudget,
        ),
      ],
    );
  }
}

class _FreeStep extends StatelessWidget {
  const _FreeStep({required this.action});
  final HabitatAction action;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.primaryContainer,
    child: Padding(
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(message),
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
    final tags = [
      nativityLabel(p.nativity),
      plantCostLabel(p.costTier),
      if (p.water == WaterNeed.low) waterLabel(p.water),
      'Blooms ${bloomRange(p)}',
    ];
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
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
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [for (final t in tags) _Tag(t)],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(text, style: const TextStyle(fontSize: 11)),
  );
}

/// Photo stand-in for the detail screen, when a plant has no credited photo.
class PlantPhotoPlaceholder extends StatelessWidget {
  const PlantPhotoPlaceholder({super.key, this.credit});

  final PhotoCredit? credit;

  @override
  Widget build(BuildContext context) => SpeciesPhoto(
    credit: credit,
    width: double.infinity,
    height: 180,
    radius: 16,
    placeholderLabel: 'Photo coming soon',
  );
}
