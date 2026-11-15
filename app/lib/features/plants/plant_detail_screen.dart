import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/content.dart';
import 'plant_finder_screen.dart' show PlantPhotoPlaceholder;
import 'plant_labels.dart';

/// One plant: size, water, sun, bloom, and the birds it helps.
/// Opened from a Plant Finder card; the back arrow returns to the list.
class PlantDetailScreen extends StatelessWidget {
  const PlantDetailScreen({
    super.key,
    required this.plant,
    required this.content,
    required this.draft,
  });

  final FinderPlant plant;
  final AppContent content;

  /// Whether the plant data is still an unreviewed draft.
  final bool draft;

  @override
  Widget build(BuildContext context) {
    final p = plant.plant;
    final text = Theme.of(context).textTheme;
    final reasons = {
      for (final l in content.repo.linksForPlant(p.id)) l.birdId: l.reason,
    };
    Widget fact(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      // A Wrap, so at large text the value moves under its label instead of
      // the label breaking mid-word.
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.start,
        spacing: 8,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 96),
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Text(value),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(p.commonName)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            PlantPhotoPlaceholder(credit: content.photos.forPlant(p.id)),
            if (content.photos.forPlant(p.id) case final c?)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Photo: ${c.author} (${c.licence})',
                  style: text.bodySmall,
                ),
              ),
            const SizedBox(height: 12),
            Text(
              p.scientificName,
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 12),
            fact('Type', plantTypeLabel(p.plantType)),
            fact('Native', nativityLabel(p.nativity)),
            fact('Size', heightLabel(p)),
            fact('Sun', p.sun.map(sunLabel).join(', ')),
            fact('Water', waterLabel(p.water)),
            fact('Blooms', bloomRange(p)),
            fact('Grows in', p.spaces.map(spaceLabel).join(', ')),
            fact('Cost', plantCostLabel(p.costTier)),
            fact('Gives birds', p.benefits.map(benefitLabel).join(', ')),
            if (p.note != null) ...[const SizedBox(height: 8), Text(p.note!)],
            const SizedBox(height: 16),
            Text(
              'Birds it helps',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (plant.birds.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('We have not linked this plant to a bird yet.'),
              )
            else
              for (final b in plant.birds)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        b.commonName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(reasons[b.id] ?? ''),
                    ],
                  ),
                ),
            const SizedBox(height: 16),
            Text(
              draft
                  ? 'Draft content, not yet reviewed. No sponsored plants.'
                  : 'No sponsored plants.',
              style: text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
