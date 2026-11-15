import 'package:material_ui/material_ui.dart';

/// EcoYard palette, taken from docs/design/EcoYard_UI_Mockup.png.
class EcoColors {
  static const forest = Color(0xFF1F5C3F);
  static const forestDark = Color(0xFF8FD0A8);
  static const leaf = Color(0xFFE3F0E5);
  static const water = Color(0xFFE2EEF8);
  static const clay = Color(0xFFFBE7DA);
  static const sand = Color(0xFFEDEFE9);
  static const tip = Color(0xFFEAF2DC);
  static const background = Color(0xFFF8FAF8);
  static const textSecondary = Color(0xFF4A6741);
}

ThemeData ecoTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: EcoColors.forest,
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? null : EcoColors.background,
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? null : EcoColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? null : Colors.white,
      indicatorColor: dark ? null : EcoColors.leaf,
    ),
  );
}

/// Padding for the scrolling lists of the five tabs. The bottom tab bar is a
/// floating glass pill and lists scroll behind it, so the bottom padding must
/// include the space it covers (`MediaQuery` reports it as `padding.bottom`).
EdgeInsets tabListPadding(BuildContext context) =>
    EdgeInsets.fromLTRB(16, 12, 16, 24 + MediaQuery.paddingOf(context).bottom);
