import 'package:material_ui/material_ui.dart';

import 'surfaces.dart';
import 'theme.dart';

/// One dropdown: a small label above the current value, a chevron on the
/// right. A bordered, tappable surface that opens a menu of the options.
///
/// Never wraps: a long value is cut with an ellipsis instead.
class FilterMenu<T> extends StatelessWidget {
  const FilterMenu({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  String get _shown {
    for (final (v, text) in options) {
      if (v == value) return text;
    }
    return '';
  }

  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final rect = topLeft & box.size;
    final t = context.eco;
    final picked = await showMenu<T>(
      context: context,
      position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
      color: t.surfaceRaised,
      items: [
        for (final (v, text) in options)
          PopupMenuItem<T>(
            value: v,
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: v == value
                      ? Icon(Icons.check, size: 18, color: t.accentText)
                      : null,
                ),
                Text(text),
              ],
            ),
          ),
      ],
    );
    if (picked != null && picked != value) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.eco;
    return Semantics(
      button: true,
      label: '$label: $_shown',
      child: ExcludeSemantics(
        child: InteractiveSurface(
          chevron: false,
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          onTap: () => _open(context),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: t.textSecondary,
                      ),
                    ),
                    Text(
                      _shown,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: t.textPrimary),
                    ),
                  ],
                ),
              ),
              Icon(Icons.keyboard_arrow_down, color: t.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Three menus side by side on one row.
class FilterMenuRow extends StatelessWidget {
  const FilterMenuRow({super.key, required this.menus});
  final List<Widget> menus;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < menus.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(child: menus[i]),
      ],
    ],
  );
}

/// The keys the three filters carry, so tests (and nothing else) can find them.
const filterSpaceKey = ValueKey('filter-space');
const filterSunKey = ValueKey('filter-sun');
const filterBudgetKey = ValueKey('filter-budget');
