import 'package:material_ui/material_ui.dart';

import '../../app/content.dart';
import '../../app/theme.dart';
import '../weather/weather_card.dart';
import '../weather/weather_controller.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.content,
    required this.weather,
    required this.now,
    required this.onIdentify,
    required this.onFindPlants,
    required this.onSmallSpace,
    required this.onMyPlan,
  });

  final AppContent content;

  /// The weather card's state. Shown above the Identify button, as drawn in
  /// the mockup.
  final WeatherController weather;

  /// The clock; its month picks today's tip.
  final DateTime Function() now;

  final VoidCallback onIdentify;
  final VoidCallback onFindPlants;
  final VoidCallback onSmallSpace;
  final VoidCallback onMyPlan;

  @override
  Widget build(BuildContext context) {
    // One tip per month, from content/tips.json. No tip for a month means no
    // tip card, not a made-up one.
    final tip = content.repo.tipForMonth(now().month);
    return ListView(
      padding: tabListPadding(context),
      children: [
        const _Header(),
        const SizedBox(height: 16),
        Text(
          'Hi there!',
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const Text("Let's make a bird-friendly space today."),
        const SizedBox(height: 16),
        WeatherCard(controller: weather),
        const SizedBox(height: 12),
        _IdentifyButton(onTap: onIdentify),
        const SizedBox(height: 12),
        _TileRow(
          onFindPlants: onFindPlants,
          onSmallSpace: onSmallSpace,
          onMyPlan: onMyPlan,
        ),
        if (tip != null) ...[
          const SizedBox(height: 12),
          _TipCard(text: tip.text, draft: content.isDraft),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.eco, color: EcoColors.forest),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'EcoYard',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: EcoColors.forest,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _IdentifyButton extends StatelessWidget {
  const _IdentifyButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: EcoColors.forest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.white24,
                child: Icon(Icons.mic, color: Colors.white),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Identify a Bird',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      'Record a sound and learn how to support it',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class _TileRow extends StatelessWidget {
  const _TileRow({
    required this.onFindPlants,
    required this.onSmallSpace,
    required this.onMyPlan,
  });
  final VoidCallback onFindPlants;
  final VoidCallback onSmallSpace;
  final VoidCallback onMyPlan;

  @override
  Widget build(BuildContext context) {
    Widget tile(String label, IconData icon, Color color, VoidCallback onTap) {
      return Expanded(
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
              child: Column(
                children: [
                  Icon(icon, color: EcoColors.forest),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // IntrinsicHeight so the three tiles are as tall as the tallest label
    // (labels wrap at large text sizes).
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tile('Find Native Plants', Icons.eco, EcoColors.leaf, onFindPlants),
          const SizedBox(width: 12),
          tile(
            'Small Space',
            Icons.local_florist,
            EcoColors.clay,
            onSmallSpace,
          ),
          const SizedBox(width: 12),
          tile('My Plan', Icons.checklist, EcoColors.sand, onMyPlan),
        ],
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard({required this.text, required this.draft});
  final String text;
  final bool draft;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EcoColors.tip,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb_outline, color: EcoColors.forest),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "This month's tip",
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                Text(text, style: const TextStyle(color: Colors.black87)),
                if (draft)
                  const Text(
                    'Draft content, not yet reviewed.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
