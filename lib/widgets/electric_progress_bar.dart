// Flutter stable 3.50 deprecates the Material umbrella library while the
// replacement package is not yet used by the rest of this Flutter app.
// ignore_for_file: deprecated_member_use

import 'dart:math' as math;
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

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.height),
      child: SizedBox(
        height: widget.height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final fillWidth = constraints.maxWidth * progress;
            return Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(
                    color: primary.withValues(alpha: 0.13),
                  ),
                ),
                if (fillWidth > 0)
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, _) => CustomPaint(
                      size: Size(fillWidth, widget.height),
                      painter: _ElectricBoltPainter(
                        phase: _pulse.value,
                        primary: primary,
                        secondary: secondary,
                        fillOpacity: 1,
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

/// A Xender-inspired transfer tile: the progress fill sits behind the file
/// details, while the original Plazma lightning branches across the filled
/// area. The icon remains visible even before progress begins.
class ElectricTransferProgressCard extends StatefulWidget {
  const ElectricTransferProgressCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.status,
    this.speed,
    this.trailing,
  });

  final Widget icon;
  final String title;
  final String subtitle;
  final double progress;
  final String status;
  final Widget? speed;
  final Widget? trailing;

  @override
  State<ElectricTransferProgressCard> createState() =>
      _ElectricTransferProgressCardState();
}

class _ElectricTransferProgressCardState
    extends State<ElectricTransferProgressCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.progress.clamp(0.0, 1.0).toDouble();
    final colors = Theme.of(context).colorScheme;
    final primary = colors.primary;
    final secondary = colors.secondary;
    final foreground = colors.onSurface;

    return ClipRRect(
      borderRadius: BorderRadius.circular(17),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: primary.withValues(alpha: 0.07),
          border: Border.all(
            color: colors.outlineVariant.withValues(alpha: 0.55),
          ),
          borderRadius: BorderRadius.circular(17),
        ),
        child: SizedBox(
          height: 92,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final fillWidth = constraints.maxWidth * progress;
              return Stack(
                children: [
                  Positioned.fill(
                    child: ColoredBox(
                      color: primary.withValues(alpha: 0.045),
                    ),
                  ),
                  if (fillWidth > 0)
                    AnimatedBuilder(
                      animation: _pulse,
                      builder: (context, _) => CustomPaint(
                        size: Size(fillWidth, constraints.maxHeight),
                        painter: _ElectricBoltPainter(
                          phase: _pulse.value,
                          primary: primary,
                          secondary: secondary,
                          fillOpacity: 0.22,
                        ),
                      ),
                    ),
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 9,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: colors.surface.withValues(alpha: 0.86),
                              borderRadius: BorderRadius.circular(13),
                              border: Border.all(
                                color: primary.withValues(alpha: 0.22),
                              ),
                            ),
                            child: widget.icon,
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        widget.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: foreground,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${(progress * 100).round()}%',
                                      style: TextStyle(
                                        color: foreground,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  widget.subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: colors.onSurfaceVariant,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        widget.status,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: colors.onSurfaceVariant,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    if (widget.speed != null) widget.speed!,
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (widget.trailing != null) ...[
                            const SizedBox(width: 3),
                            widget.trailing!,
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
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
    required this.fillOpacity,
  });

  final double phase;
  final Color primary;
  final Color secondary;
  final double fillOpacity;

  double _mainY(double x, Size size) {
    final ratio = size.width <= 0 ? 0.0 : x / size.width;
    final wave = math.sin(ratio * 8.5 + phase * math.pi * 2) * size.height * 0.105;
    final detail = math.cos(ratio * 18.0 - phase * math.pi * 2) * size.height * 0.045;
    return (size.height * 0.5 + wave + detail)
        .clamp(size.height * 0.16, size.height * 0.84)
        .toDouble();
  }

  void _drawLightning(
    Canvas canvas,
    ui.Path path,
    Color glowColor, {
    required double glowWidth,
    required double coreWidth,
  }) {
    final glow = Paint()
      ..color = glowColor.withValues(alpha: 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = glowWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawPath(path, glow);

    final core = Paint()
      ..color = Colors.white.withValues(alpha: 0.96)
      ..style = PaintingStyle.stroke
      ..strokeWidth = coreWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, core);
  }

  ui.Path _branchPath({
    required double startX,
    required double startY,
    required int branchIndex,
    required int direction,
    required Size size,
    double reach = 0.43,
  }) {
    final path = ui.Path()..moveTo(startX, startY);
    final steps = size.height > 28 ? 5 : 3;
    for (var step = 1; step <= steps; step++) {
      final t = step / steps;
      final jitter = math.sin(branchIndex * 2.7 + step * 4.1 + phase * 3) *
          size.height * 0.055;
      final drift = math.cos(branchIndex * 1.9 + step * 2.3) *
          size.width * 0.008;
      final x = (startX + size.width * 0.035 * t + drift)
          .clamp(0.0, size.width)
          .toDouble();
      final y = (startY + direction * size.height * reach * t + jitter)
          .clamp(1.0, math.max(1.0, size.height - 1.0))
          .toDouble();
      path.lineTo(x, y);
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final rect = Offset.zero & size;
    final radius = Radius.circular(math.min(size.height * 0.24, size.width * 0.5));
    final glow = Paint()
      ..color = primary.withValues(alpha: 0.58 * fillOpacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), glow);

    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Color.lerp(primary, Colors.white, 0.2)!
              .withValues(alpha: fillOpacity),
          primary.withValues(alpha: fillOpacity),
          secondary.withValues(alpha: fillOpacity),
        ],
      ).createShader(rect);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), fill);

    final glowColor = Color.lerp(primary, Colors.white, 0.82)!;
    final main = ui.Path()..moveTo(0, _mainY(0, size));
    final segments = (size.width / 12).ceil().clamp(1, 240);
    for (var i = 1; i <= segments; i++) {
      final x = size.width * i / segments;
      main.lineTo(x, _mainY(x, size));
    }

    // Main horizontal discharge: its visible length is exactly the filled
    // portion of the transfer tile.
    _drawLightning(
      canvas,
      main,
      glowColor,
      glowWidth: math.max(1.2, size.height * 0.045),
      coreWidth: math.max(0.7, size.height * 0.014),
    );

    // Forks branch both above and below the main discharge. Their anchors
    // are distributed across the current fill, so the network grows from
    // left to right with the transfer rather than appearing as one bolt.
    final branchCount = (size.width / 27).floor().clamp(1, 22);
    for (var i = 0; i < branchCount; i++) {
      final anchorX = size.width * (i + 0.5) / branchCount;
      final anchorY = _mainY(anchorX, size);
      final direction = i.isEven ? -1 : 1;
      final branch = _branchPath(
        startX: anchorX,
        startY: anchorY,
        branchIndex: i,
        direction: direction,
        size: size,
        reach: 0.42,
      );
      _drawLightning(
        canvas,
        branch,
        glowColor,
        glowWidth: math.max(1.0, size.height * 0.027),
        coreWidth: math.max(0.55, size.height * 0.009),
      );

      // A shorter counter-fork creates the irregular, branching storm look.
      if (i.isEven || size.height > 26) {
        final forkX = (anchorX + size.width * 0.012).clamp(0.0, size.width);
        final forkY = _mainY(forkX, size) + direction * size.height * 0.19;
        final fork = _branchPath(
          startX: forkX,
          startY: forkY.clamp(1.0, math.max(1.0, size.height - 1.0)).toDouble(),
          branchIndex: i + 31,
          direction: -direction,
          size: size,
          reach: 0.22,
        );
        _drawLightning(
          canvas,
          fork,
          glowColor,
          glowWidth: math.max(0.8, size.height * 0.018),
          coreWidth: math.max(0.5, size.height * 0.007),
        );
      }
    }

    final sparkX = size.width * phase;
    final sparkPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawCircle(
      Offset(sparkX, _mainY(sparkX, size)),
      math.max(1.4, size.height * 0.055),
      sparkPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ElectricBoltPainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.primary != primary ||
      oldDelegate.secondary != secondary ||
      oldDelegate.fillOpacity != fillOpacity;
}
