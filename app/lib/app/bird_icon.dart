import 'package:material_ui/material_ui.dart';

/// The EcoYard bird, drawn to match the app icon, for the Birds tab.
///
/// Material has no bird glyph (the tab showed Flutter's Dash mascot before),
/// so this is a small painted silhouette: outline when the tab is not
/// selected, filled when it is.
class BirdIcon extends StatelessWidget {
  const BirdIcon({super.key, this.filled = false, this.size = 24});

  final bool filled;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color =
        IconTheme.of(context).color ?? Theme.of(context).iconTheme.color;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _BirdPainter(
          color: color ?? const Color(0xFF1F5C3F),
          filled: filled,
        ),
      ),
    );
  }
}

class _BirdPainter extends CustomPainter {
  const _BirdPainter({required this.color, required this.filled});

  final Color color;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    double x(double v) => v * s;

    // Body and head as one rounded silhouette, with a swept tail and a beak:
    // the same shapes as docs/design/app_icon.svg, simplified for 24 px.
    final body = Path()
      ..moveTo(x(4.2), x(12.6))
      // back, up over the shoulder to the head
      ..cubicTo(x(5.4), x(8.6), x(9.4), x(7.2), x(12.6), x(8.4))
      ..cubicTo(x(13.2), x(6.4), x(15.4), x(5.6), x(16.9), x(6.9))
      ..cubicTo(x(18.1), x(7.9), x(18.2), x(9.4), x(17.4), x(10.4))
      // beak
      ..lineTo(x(21.4), x(10.9))
      ..lineTo(x(17.3), x(12.3))
      // breast and belly down to the tail
      ..cubicTo(x(17.2), x(15.4), x(14.6), x(17.6), x(11.3), x(17.6))
      ..cubicTo(x(8.6), x(17.6), x(6.6), x(16.4), x(5.6), x(14.8))
      // tail sweeping back and up
      ..lineTo(x(1.6), x(15.6))
      ..close();

    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;
    if (filled) {
      canvas.drawPath(body, paint..style = PaintingStyle.fill);
    } else {
      canvas.drawPath(
        body,
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = x(1.7)
          ..strokeJoin = StrokeJoin.round,
      );
    }
    // Eye: a dot when filled is punched out, a small dot when outlined.
    final eye = Offset(x(15.8), x(9.4));
    canvas.drawCircle(
      eye,
      x(filled ? 1.0 : 0.9),
      Paint()
        ..color = filled ? const Color(0x00000000) : color
        ..blendMode = filled ? BlendMode.clear : BlendMode.srcOver,
    );
  }

  @override
  bool shouldRepaint(_BirdPainter old) =>
      old.color != color || old.filled != filled;
}
