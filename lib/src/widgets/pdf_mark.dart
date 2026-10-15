import 'package:flutter/material.dart';

import '../theme.dart';

/// The ToolPDF View mark: a white outlined sheet with a folded corner on the
/// brand red. Drawn instead of shipped as an image so it stays sharp at any
/// size and adds nothing to the download.
class PdfMark extends StatelessWidget {
  const PdfMark({super.key, this.size = 48, this.filled = true, this.color});

  /// Side of the (square) mark in logical pixels.
  final double size;

  /// Whether to paint the red rounded square behind the sheet.
  final bool filled;

  /// Colour of the sheet; defaults to white on red, brand red otherwise.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _PdfMarkPainter(
          filled: filled,
          sheetColor: color ?? (filled ? Colors.white : kBrandRed),
        ),
      ),
    );
  }
}

class _PdfMarkPainter extends CustomPainter {
  _PdfMarkPainter({required this.filled, required this.sheetColor});

  final bool filled;
  final Color sheetColor;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    if (filled) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, s, s),
          Radius.circular(s * 0.22),
        ),
        Paint()..color = kBrandRed,
      );
    }

    final stroke = Paint()
      ..color = sheetColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * (filled ? 0.055 : 0.07)
      ..strokeJoin = StrokeJoin.round;

    final inset = filled ? 0.26 : 0.17;
    final left = s * inset;
    final right = s * (1 - inset);
    final top = s * (filled ? 0.17 : 0.06);
    final bottom = s * (filled ? 0.83 : 0.94);
    final fold = (right - left) * 0.32;

    final sheet = Path()
      ..moveTo(left, top)
      ..lineTo(right - fold, top)
      ..lineTo(right, top + fold)
      ..lineTo(right, bottom)
      ..lineTo(left, bottom)
      ..close();
    canvas.drawPath(sheet, stroke);
    canvas.drawPath(
      Path()
        ..moveTo(right - fold, top)
        ..lineTo(right - fold, top + fold)
        ..lineTo(right, top + fold),
      stroke,
    );

    final label = TextPainter(
      text: TextSpan(
        text: 'PDF',
        style: TextStyle(
          color: sheetColor,
          fontSize: s * 0.21,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(
      canvas,
      Offset((s - label.width) / 2, bottom - label.height - s * 0.11),
    );
  }

  @override
  bool shouldRepaint(_PdfMarkPainter old) =>
      old.filled != filled || old.sheetColor != sheetColor;
}
