import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:material_ui/material_ui.dart';

/// A species photo, or an honest placeholder when we have none.
///
/// A photo is only ever shown when [PhotoCredits] has a credit for it, so a
/// picture can never appear without the author and licence we owe it. The
/// credit itself is listed in Settings > About > Photo credits.
class SpeciesPhoto extends StatelessWidget {
  const SpeciesPhoto({
    super.key,
    required this.credit,
    required this.width,
    required this.height,
    this.radius = 12,
    this.placeholderLabel,
  });

  final PhotoCredit? credit;
  final double width;
  final double height;
  final double radius;

  /// Shown under the leaf when there is no photo and there is room.
  final String? placeholderLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shape = BorderRadius.circular(radius);
    final c = credit;
    if (c == null) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: shape,
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.eco, size: height < 80 ? height * 0.5 : 48),
            if (placeholderLabel != null && height >= 80) ...[
              const SizedBox(height: 4),
              Text(placeholderLabel!),
            ],
          ],
        ),
      );
    }
    return ClipRRect(
      borderRadius: shape,
      child: Image.asset(
        c.asset,
        width: width,
        height: height,
        fit: BoxFit.cover,
        // A missing or broken file falls back to the placeholder rather than
        // showing a broken image.
        errorBuilder: (context, _, _) => SpeciesPhoto(
          credit: null,
          width: width,
          height: height,
          radius: radius,
          placeholderLabel: placeholderLabel,
        ),
      ),
    );
  }
}
