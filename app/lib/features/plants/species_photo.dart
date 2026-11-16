import 'package:ecoyard_core/ecoyard_core.dart';
import 'package:material_ui/material_ui.dart';

/// How a hero photo is shaped: its own aspect ratio, kept within limits so
/// a very tall or very wide picture cannot take over the screen. Within the
/// limits nothing is cropped; outside them the crop favours the upper part,
/// where a bird's head is.
double heroAspect(PhotoCredit? c) {
  const narrowest = 0.8; // tallest we allow (taller photos lose their foot)
  const widest = 1.6;
  final a = c?.aspectRatio ?? 1.33;
  return a.clamp(narrowest, widest);
}

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
  }) : keepShape = false;

  /// A large photo that keeps its own shape instead of being cut to a fixed
  /// box. Fills the available width; its height follows the photo.
  const SpeciesPhoto.hero({
    super.key,
    required this.credit,
    this.radius = 14,
    this.placeholderLabel,
  }) : width = double.infinity,
       height = 0,
       keepShape = true;

  /// True for [SpeciesPhoto.hero]: size from the photo, not from [height].
  final bool keepShape;

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
    if (keepShape) {
      final aspect = heroAspect(c);
      return AspectRatio(
        aspectRatio: aspect,
        child: LayoutBuilder(
          builder: (context, box) => SpeciesPhoto(
            credit: c,
            width: box.maxWidth,
            height: box.maxHeight,
            radius: radius,
            placeholderLabel: placeholderLabel,
          ),
        ),
      );
    }
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
        // Birds' heads are in the upper part of the picture.
        alignment: const Alignment(0, -0.5),
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
