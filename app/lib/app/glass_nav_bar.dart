import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';

/// A floating, frosted-glass tab bar in the style of recent iOS: a rounded,
/// translucent pill that blurs whatever scrolls underneath it.
///
/// Used with `Scaffold(extendBody: true)`, so lists run behind the bar and
/// the screens add `MediaQuery.paddingOf(context).bottom` to their bottom
/// padding (see [tabListPadding]) to stay reachable.
class GlassNavBar extends StatelessWidget {
  const GlassNavBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.destinations,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<NavigationDestination> destinations;

  static const double _radius = 30;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final glass = dark
        ? const Color(0xFF16201A).withValues(alpha: 0.55)
        : Colors.white.withValues(alpha: 0.62);
    final edge = Colors.white.withValues(alpha: dark ? 0.14 : 0.7);

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: DecoratedBox(
          // The soft shadow sits outside the clip so it is not cut off.
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_radius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.35 : 0.12),
                blurRadius: 24,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_radius),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: glass,
                  borderRadius: BorderRadius.circular(_radius),
                  border: Border.all(color: edge, width: 1),
                ),
                child: NavigationBarTheme(
                  data: NavigationBarThemeData(
                    backgroundColor: Colors.transparent,
                    surfaceTintColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    elevation: 0,
                    height: 68,
                    indicatorColor: theme.colorScheme.primary.withValues(
                      alpha: dark ? 0.30 : 0.16,
                    ),
                  ),
                  child: NavigationBar(
                    selectedIndex: selectedIndex,
                    onDestinationSelected: onSelected,
                    destinations: destinations,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
