import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A flower made of overlapping circles.
class FlowerShape extends StatelessWidget {
  const FlowerShape({
    super.key,
    required this.size,
    required this.color,
    this.petals = 8,
  });

  final double size;
  final Color color;
  final int petals;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _FlowerPainter(color, petals),
  );
}

class _FlowerPainter extends CustomPainter {
  _FlowerPainter(this.color, this.petals);

  final Color color;
  final int petals;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final center = size.center(Offset.zero);
    final radius = size.width / 4.2;
    for (var i = 0; i < petals; i++) {
      final angle = 2 * math.pi * i / petals;
      canvas.drawCircle(
        center + Offset(math.cos(angle), math.sin(angle)) * radius,
        radius,
        paint,
      );
    }
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(_FlowerPainter old) =>
      old.color != color || old.petals != petals;
}

/// Concentric rings, like a target.
class TargetShape extends StatelessWidget {
  const TargetShape({
    super.key,
    required this.size,
    required this.color,
    this.background = AppColors.background,
    this.rings = 3,
  });

  final double size;
  final Color color;
  final Color background;
  final int rings;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (var i = rings * 2; i >= 1; i--)
            Container(
              width: size * i / (rings * 2),
              height: size * i / (rings * 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i.isEven ? color : background,
              ),
            ),
        ],
      ),
    );
  }
}

/// The collage of tiles shown at the top of the sign-in screen.
class HeroCollage extends StatelessWidget {
  const HeroCollage({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tile = (constraints.maxWidth - 12) / 2;
        return SizedBox(
          height: tile * 2 + 12,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                child: _Tile(
                  size: tile,
                  color: AppColors.lavender,
                  child: FlowerShape(size: tile * 0.62, color: AppColors.blue),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: _Tile(
                  size: tile,
                  color: AppColors.surface,
                  child: TargetShape(
                    size: tile * 0.7,
                    color: AppColors.pink,
                    background: AppColors.surface,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                bottom: 0,
                child: _Tile(
                  size: tile,
                  color: AppColors.lime,
                  child: Text(
                    '₹',
                    style: TextStyle(
                      fontSize: tile * 0.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                      height: 1,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: _Tile(
                  size: tile,
                  color: AppColors.pink,
                  radius: tile / 2,
                  child: Icon(
                    Icons.south_rounded,
                    size: tile * 0.45,
                    color: AppColors.ink,
                  ),
                ),
              ),
              Positioned(
                left: tile - 22,
                top: tile - 22,
                child: FlowerShape(size: 56, color: AppColors.lime, petals: 6),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.size,
    required this.color,
    required this.child,
    this.radius = 28,
  });

  final double size;
  final Color color;
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
    ),
    child: child,
  );
}
