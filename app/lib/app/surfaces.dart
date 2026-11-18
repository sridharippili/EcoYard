import 'package:material_ui/material_ui.dart';

import 'theme.dart';

const double surfaceRadius = 16;

/// Read-only content: tips, explanations, results. A tinted fill with no
/// border, no chevron and no pressed state. If it needs to be tapped it is the
/// wrong surface: use [InteractiveSurface].
class InfoSurface extends StatelessWidget {
  const InfoSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: context.eco.surfaceInfo,
      borderRadius: BorderRadius.circular(surfaceRadius),
    ),
    child: child,
  );
}

/// Anything tappable that is not the primary action: a raised surface with a
/// 1px border, a chevron (or a control of its own) on the trailing edge, and a
/// visible pressed state.
class InteractiveSurface extends StatelessWidget {
  const InteractiveSurface({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.chevron = true,
    this.color,
  });

  final Widget child;

  /// Null for a surface whose own controls do the work (a switch, buttons).
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  /// Shown when [onTap] is set. Turn off when the row has its own control.
  final bool chevron;

  /// A tint for the surface (the Home tiles). Defaults to the raised colour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.eco;
    final body = Padding(
      padding: padding,
      child: onTap != null && chevron
          ? Row(
              children: [
                Expanded(child: child),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, color: t.textSecondary),
              ],
            )
          : child,
    );
    return Material(
      color: color ?? t.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(surfaceRadius),
        side: BorderSide(color: t.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? body
          : InkWell(
              onTap: onTap,
              splashColor: t.accent.withValues(alpha: 0.14),
              highlightColor: t.accent.withValues(alpha: 0.10),
              child: body,
            ),
    );
  }
}

/// The screen's one main action: filled accent, [EcoTokens.accentOn] text,
/// full width.
class PrimaryAction extends StatelessWidget {
  const PrimaryAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: icon == null
        ? FilledButton(onPressed: onPressed, child: Text(label))
        : FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            label: Text(label),
          ),
  );
}

/// The "Free" / "Low cost" badge, in its own colours for each theme.
class CostBadge extends StatelessWidget {
  const CostBadge({super.key, required this.free});
  final bool free;

  @override
  Widget build(BuildContext context) {
    final t = context.eco;
    return InfoPill(
      label: free ? 'Free' : 'Low cost',
      background: free ? t.badgeFree : t.badgeLowCost,
      foreground: free ? t.badgeFreeOn : t.badgeLowCostOn,
    );
  }
}

/// A small read-only pill.
class InfoPill extends StatelessWidget {
  const InfoPill({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: foreground,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
