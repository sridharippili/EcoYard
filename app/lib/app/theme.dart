import 'package:material_ui/material_ui.dart';

/// EcoYard's colours, by meaning rather than by shade. Every value has a
/// light and a dark version and the screens ask for the meaning
/// (`context.eco.surfaceInfo`), never for a colour, so the app follows the
/// device's light or dark setting everywhere.
///
/// Three surface levels, and the rule that holds them together:
/// tinted fill means "read only", a border means "you can tap it".
///  - primary action: filled [accent] with [accentOn] text, full width, at
///    most one per screen;
///  - interactive surface: [surfaceRaised] with a 1px [border];
///  - information surface: [surfaceInfo], no border, no chevron.
@immutable
class EcoTokens extends ThemeExtension<EcoTokens> {
  const EcoTokens({
    required this.background,
    required this.surfaceRaised,
    required this.surfaceInfo,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    required this.accentOn,
    required this.accentText,
    required this.badgeFree,
    required this.badgeFreeOn,
    required this.badgeLowCost,
    required this.badgeLowCostOn,
    required this.destructive,
    required this.tileGreen,
    required this.tileClay,
    required this.tileSand,
  });

  /// The page.
  final Color background;

  /// Tappable things: rows, cards, tiles. Always drawn with a [border].
  final Color surfaceRaised;

  /// Read-only things: tips, explanations, results. Never tappable.
  final Color surfaceInfo;

  final Color border;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;

  /// The dark green fill of the primary action, and [accentOn] on top of it.
  final Color accent;
  final Color accentOn;

  /// The same green as text or an icon on the page and on the surfaces
  /// (lighter in dark mode, where [accent] would be too dim to read).
  final Color accentText;

  final Color badgeFree;
  final Color badgeFreeOn;
  final Color badgeLowCost;
  final Color badgeLowCostOn;

  /// Delete and other irreversible actions.
  final Color destructive;

  /// The tints of the Home tiles. They are categories, so each has its own
  /// colour; the tiles still carry a border because they are tappable.
  final Color tileGreen;
  final Color tileClay;
  final Color tileSand;

  static const light = EcoTokens(
    background: Color(0xFFF7FAF7),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceInfo: Color(0xFFE8F1E8),
    border: Color(0xFFD3DDD5),
    borderStrong: Color(0xFF7F9487),
    textPrimary: Color(0xFF15201A),
    textSecondary: Color(0xFF475F50),
    accent: Color(0xFF1F5C3F),
    accentOn: Color(0xFFFFFFFF),
    accentText: Color(0xFF1F5C3F),
    badgeFree: Color(0xFFDDEFE2),
    badgeFreeOn: Color(0xFF1B5538),
    badgeLowCost: Color(0xFFFFEBD2),
    badgeLowCostOn: Color(0xFF7A4100),
    destructive: Color(0xFFB3261E),
    tileGreen: Color(0xFFE3F0E5),
    tileClay: Color(0xFFFBE7DA),
    tileSand: Color(0xFFEDEFE9),
  );

  /// The info surface is a desaturated near-black green (about 10%
  /// lightness), not a darkened pastel, so it does not glow.
  static const dark = EcoTokens(
    background: Color(0xFF0C120E),
    surfaceRaised: Color(0xFF1D2821),
    surfaceInfo: Color(0xFF16211A),
    border: Color(0xFF33423A),
    borderStrong: Color(0xFF7E9686),
    textPrimary: Color(0xFFE9F0EA),
    textSecondary: Color(0xFFA8BBAE),
    accent: Color(0xFF2A7A54),
    accentOn: Color(0xFFFFFFFF),
    accentText: Color(0xFF8FD0A8),
    badgeFree: Color(0xFF1E3A2B),
    badgeFreeOn: Color(0xFFA9E3BF),
    badgeLowCost: Color(0xFF3B2A12),
    badgeLowCostOn: Color(0xFFFFC47D),
    destructive: Color(0xFFFF8F86),
    tileGreen: Color(0xFF1A2B20),
    tileClay: Color(0xFF2E2119),
    tileSand: Color(0xFF23251F),
  );

  @override
  EcoTokens copyWith({
    Color? background,
    Color? surfaceRaised,
    Color? surfaceInfo,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? accent,
    Color? accentOn,
    Color? accentText,
    Color? badgeFree,
    Color? badgeFreeOn,
    Color? badgeLowCost,
    Color? badgeLowCostOn,
    Color? destructive,
    Color? tileGreen,
    Color? tileClay,
    Color? tileSand,
  }) => EcoTokens(
    background: background ?? this.background,
    surfaceRaised: surfaceRaised ?? this.surfaceRaised,
    surfaceInfo: surfaceInfo ?? this.surfaceInfo,
    border: border ?? this.border,
    borderStrong: borderStrong ?? this.borderStrong,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    accent: accent ?? this.accent,
    accentOn: accentOn ?? this.accentOn,
    accentText: accentText ?? this.accentText,
    badgeFree: badgeFree ?? this.badgeFree,
    badgeFreeOn: badgeFreeOn ?? this.badgeFreeOn,
    badgeLowCost: badgeLowCost ?? this.badgeLowCost,
    badgeLowCostOn: badgeLowCostOn ?? this.badgeLowCostOn,
    destructive: destructive ?? this.destructive,
    tileGreen: tileGreen ?? this.tileGreen,
    tileClay: tileClay ?? this.tileClay,
    tileSand: tileSand ?? this.tileSand,
  );

  @override
  EcoTokens lerp(ThemeExtension<EcoTokens>? other, double t) {
    if (other is! EcoTokens) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return EcoTokens(
      background: c(background, other.background),
      surfaceRaised: c(surfaceRaised, other.surfaceRaised),
      surfaceInfo: c(surfaceInfo, other.surfaceInfo),
      border: c(border, other.border),
      borderStrong: c(borderStrong, other.borderStrong),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      accent: c(accent, other.accent),
      accentOn: c(accentOn, other.accentOn),
      accentText: c(accentText, other.accentText),
      badgeFree: c(badgeFree, other.badgeFree),
      badgeFreeOn: c(badgeFreeOn, other.badgeFreeOn),
      badgeLowCost: c(badgeLowCost, other.badgeLowCost),
      badgeLowCostOn: c(badgeLowCostOn, other.badgeLowCostOn),
      destructive: c(destructive, other.destructive),
      tileGreen: c(tileGreen, other.tileGreen),
      tileClay: c(tileClay, other.tileClay),
      tileSand: c(tileSand, other.tileSand),
    );
  }
}

extension EcoContext on BuildContext {
  /// The colours by meaning, for the current light or dark setting.
  EcoTokens get eco =>
      Theme.of(this).extension<EcoTokens>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? EcoTokens.dark
          : EcoTokens.light);
}

const _radius = 16.0;

ThemeData ecoTheme(Brightness brightness) {
  final t = brightness == Brightness.dark ? EcoTokens.dark : EcoTokens.light;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: EcoTokens.light.accent,
        brightness: brightness,
      ).copyWith(
        primary: t.accent,
        onPrimary: t.accentOn,
        surface: t.background,
        onSurface: t.textPrimary,
        onSurfaceVariant: t.textSecondary,
        outline: t.borderStrong,
        outlineVariant: t.border,
        error: t.destructive,
      );
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(_radius),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    extensions: [t],
    scaffoldBackgroundColor: t.background,
    appBarTheme: AppBarTheme(
      backgroundColor: t.background,
      foregroundColor: t.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: t.surfaceRaised,
      indicatorColor: t.surfaceInfo,
    ),
    // A Card that is not given a colour is a tappable surface: raised, with a
    // border. Read-only things use InfoSurface instead.
    cardTheme: CardThemeData(
      color: t.surfaceRaised,
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shape: shape.copyWith(side: BorderSide(color: t.border)),
    ),
    dividerTheme: DividerThemeData(color: t.border, space: 1),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: t.accentText),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.accentText,
        side: BorderSide(color: t.borderStrong),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.accent,
        foregroundColor: t.accentOn,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: t.surfaceRaised,
      selectedColor: t.surfaceInfo,
      side: BorderSide(color: t.border),
      labelStyle: TextStyle(color: t.textPrimary),
      checkmarkColor: t.accentText,
    ),
  );
}

/// Padding for the scrolling lists of the five tabs. The bottom tab bar is a
/// floating glass pill and lists scroll behind it, so the bottom padding must
/// include the space it covers (`MediaQuery` reports it as `padding.bottom`).
EdgeInsets tabListPadding(BuildContext context) =>
    EdgeInsets.fromLTRB(16, 12, 16, 24 + MediaQuery.paddingOf(context).bottom);
