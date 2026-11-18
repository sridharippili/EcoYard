import 'package:material_ui/material_ui.dart';

import '../../app/content.dart';
import '../../app/surfaces.dart';
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
    // The green for text and icons: dark on a light screen, light on a dark
    // one, so the title is readable in both.
    final green = context.eco.accentText;
    return Row(
      children: [
        Icon(Icons.eco, color: green),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'EcoYard',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(color: green, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

/// The screen's one primary action: filled accent, full width.
class _IdentifyButton extends StatelessWidget {
  const _IdentifyButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.eco;
    return Material(
      color: t.accent,
      borderRadius: BorderRadius.circular(surfaceRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(surfaceRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: t.accentOn.withValues(alpha: 0.20),
                child: Icon(Icons.mic, color: t.accentOn),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Identify a Bird',
                      style: TextStyle(
                        color: t.accentOn,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      'Record a sound and learn how to support it',
                      style: TextStyle(
                        color: t.accentOn.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: t.accentOn),
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
    final t = context.eco;
    // Tappable, so each keeps its border; each category has its own tint.
    Widget tile(
      String label,
      IconData icon,
      Color tint,
      VoidCallback onTap, {
      String? subtitle,
    }) {
      return Expanded(
        child: InteractiveSurface(
          onTap: onTap,
          chevron: false,
          color: tint,
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, color: t.accentText),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: t.textPrimary,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: t.textSecondary),
                ),
            ],
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
          tile('Find Native Plants', Icons.eco, t.tileGreen, onFindPlants),
          const SizedBox(width: 12),
          tile(
            'Small Space',
            Icons.local_florist,
            t.tileClay,
            onSmallSpace,
            subtitle: 'Balcony or containers',
          ),
          const SizedBox(width: 12),
          tile('My Plan', Icons.checklist, t.tileSand, onMyPlan),
        ],
      ),
    );
  }
}

/// Read-only: an information surface.
class _TipCard extends StatelessWidget {
  const _TipCard({required this.text, required this.draft});
  final String text;
  final bool draft;

  @override
  Widget build(BuildContext context) {
    final t = context.eco;
    return InfoSurface(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline, color: t.accentText),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "This month's tip",
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary,
                  ),
                ),
                Text(text, style: TextStyle(color: t.textPrimary)),
                if (draft)
                  Text(
                    'Draft content, not yet reviewed.',
                    style: TextStyle(fontSize: 12, color: t.textSecondary),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
