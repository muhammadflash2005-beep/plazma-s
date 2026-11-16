// Flutter stable 3.50 deprecates the Material umbrella library while the
// replacement package is not yet used by the rest of this Flutter app.
// ignore_for_file: deprecated_member_use

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class ElectricProgressBar extends StatefulWidget {
  const ElectricProgressBar({
    super.key,
    required this.value,
    this.height = 8,
  });

  final double value;
  final double height;

  @override
  State<ElectricProgressBar> createState() => _ElectricProgressBarState();
}

class _ElectricProgressBarState extends State<ElectricProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1250),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.value.clamp(0.0, 1.0).toDouble();
    final colors = Theme.of(context).colorScheme;
    final primary = colors.primary;
    final secondary = colors.secondary;
    final track = colors.primary.withValues(alpha: 0.13);
    final boltGlow = Color.lerp(primary, colors.onPrimary, 0.62)!;

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.height),
      child: SizedBox(
        height: widget.height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final fillWidth = constraints.maxWidth * progress;
            return Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: track)),
                if (fillWidth > 0)
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, _) => CustomPaint(
                      size: Size(fillWidth, widget.height),
                      painter: _ElectricBoltPainter(
                        phase: _pulse.value,
                        primary: primary,
                        secondary: secondary,
                        boltGlow: boltGlow,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ElectricBoltPainter extends CustomPainter {
  const _ElectricBoltPainter({
    required this.phase,
    required this.primary,
    required this.secondary,
    required this.boltGlow,
  });

  final double phase;
  final Color primary;
  final Color secondary;
  final Color boltGlow;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final glow = Paint()
      ..color = primary.withValues(alpha: 0.82)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(size.height)),
      glow,
    );

    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Color.lerp(primary, Colors.white, 0.18)!,
          primary,
          secondary,
        ],
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(size.height)),
      fill,
    );

    final path = ui.Path();
    final mid = size.height / 2;
    path.moveTo(0, mid);
    final segments = (size.width / 13).ceil().clamp(1, 180);
    for (var i = 1; i <= segments; i++) {
      final x = size.width * i / segments;
      final wave = ((i * 17) % 11 - 5) * size.height * 0.075;
      final spark =
          (i / segments - phase).abs() < 0.045 ? -size.height * 0.28 : 0.0;
      path.lineTo(
        x,
        (mid + wave + spark).clamp(1.0, size.height - 1.0).toDouble(),
      );
    }

    final boltGlowPaint = Paint()
      ..color = boltGlow
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.height * 0.36).clamp(1.0, 3.0).toDouble()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawPath(path, boltGlowPaint);

    final boltCore = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.height * 0.13).clamp(0.8, 1.5).toDouble()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, boltCore);

    final sparkPaint = Paint()
      ..color = Colors.white
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawCircle(
      Offset(size.width * phase, mid),
      size.height * 0.38,
      sparkPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ElectricBoltPainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.primary != primary ||
      oldDelegate.secondary != secondary ||
      oldDelegate.boltGlow != boltGlow;
}
