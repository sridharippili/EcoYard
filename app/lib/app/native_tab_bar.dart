import 'package:cupertino_native/cupertino_native.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'theme.dart';

/// Whether the five tabs are drawn by the system (the real iOS tab bar, which
/// is Liquid Glass on iOS 26 and later). Everywhere else the Flutter-drawn
/// glass bar is used.
bool useSystemTabBar() =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// The system tab bar, through `cupertino_native`. It draws and animates
/// itself, so nothing here imitates glass.
class SystemTabBar extends StatelessWidget {
  const SystemTabBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// Same five tabs, in the same order, as the Flutter-drawn bar.
  static const items = [
    CNTabBarItem(label: 'Home', icon: CNSymbol('house')),
    CNTabBarItem(label: 'Plants', icon: CNSymbol('leaf')),
    CNTabBarItem(label: 'Birds', icon: CNSymbol('bird')),
    CNTabBarItem(label: 'My Plan', icon: CNSymbol('checklist')),
    CNTabBarItem(label: 'Settings', icon: CNSymbol('gearshape')),
  ];

  @override
  Widget build(BuildContext context) {
    // The native bar draws its unselected icons and labels in a fixed dark
    // colour, which is unreadable on its dark glass style. So it always uses
    // the light glass style, with a dark green selected tab, in both modes.
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Theme(
      data: ecoTheme(Brightness.light),
      child: CNTabBar(
        items: items,
        currentIndex: selectedIndex,
        onTap: onSelected,
        // White on the grey glass of a dark screen, dark green on a light one.
        tint: dark ? Colors.white : EcoTokens.light.accent,
        shrinkCentered: false,
      ),
    );
  }
}
