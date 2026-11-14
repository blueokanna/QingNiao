import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'aurora_engine.dart';
import 'aurora_theme.dart';
import '../app/app_settings.dart';

/// 全局极光背景。
///
/// 设计要点：
/// * 唯一实例由各个页面的 [AuroraScaffold] 复用同一全局时钟，页面切换不会
///   重启时间线，视觉上是一条持续流动的极光；
/// * 所有光团使用径向渐变直接绘制，避免逐帧 `blur`；
/// * 质量档位决定光团数量、星点与帧率，滚动时进一步退避；
/// * 整层包在 `RepaintBoundary` 中，列表滚动不会触发背景重绘。
class AuroraBackdrop extends StatelessWidget {
  const AuroraBackdrop({super.key, this.veil = true});

  final bool veil;

  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).brightness == Brightness.dark &&
        AppScope.maybeOf(context)?.amoled == true) {
      return const ColoredBox(color: Colors.black);
    }
    final engine = AuroraEngine.instance;
    final colors = context.aurora;
    final scheme = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([engine.clock, engine]),
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          isComplex: true,
          willChange: !engine.reduceMotion,
          painter: _AuroraPainter(
            time: engine.reduceMotion ? 0 : engine.clock.value,
            dark: dark,
            colors: colors,
            surface: scheme.surface,
            quality: engine.quality,
            scrolling: engine.scrolling,
            veil: veil,
          ),
        ),
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter({
    required this.time,
    required this.dark,
    required this.colors,
    required this.surface,
    required this.quality,
    required this.scrolling,
    required this.veil,
  });

  final double time;
  final bool dark;
  final AuroraColors colors;
  final Color surface;
  final AuroraQuality quality;
  final bool scrolling;
  final bool veil;

  static final List<_Blob> _blobs = [
    _Blob(-.18, .08, 1.05, 0, .085, 0, 0),
    _Blob(.98, -.04, .82, 1, .061, 1.7, 1),
    _Blob(.78, .52, 1.2, 2, .045, 3.1, 2),
    _Blob(-.12, .82, .92, 0, .073, 4.2, 1),
    _Blob(.42, .3, .64, 1, .11, 5.6, 2),
  ];

  static final List<_Star> _stars = _seedStars();

  static List<_Star> _seedStars() {
    final random = math.Random(9031);
    return List.generate(46, (_) {
      return _Star(
        random.nextDouble(),
        random.nextDouble() * .72,
        random.nextDouble(),
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? [
                  Color.alphaBlend(
                    colors.auroraA.withValues(alpha: .07),
                    surface,
                  ),
                  surface,
                ]
              : [
                  surface,
                  Color.alphaBlend(
                    colors.auroraC.withValues(alpha: .03),
                    surface,
                  ),
                ],
        ).createShader(rect),
    );

    final count = switch (quality) {
      AuroraQuality.full => _blobs.length,
      AuroraQuality.balanced => 3,
      AuroraQuality.efficient => 2,
    };
    final amplitude = scrolling ? .35 : 1.0;
    canvas.save();
    for (var index = 0; index < count; index++) {
      final blob = _blobs[index];
      final drift = time * blob.speed;
      final cx =
          size.width *
          (blob.x + math.sin(drift + blob.phase) * .045 * amplitude);
      final cy =
          size.height *
          (blob.y + math.cos(drift * .8 + blob.phase) * .03 * amplitude);
      final radius = size.shortestSide * blob.radius;
      final color = switch (blob.color) {
        0 => colors.auroraA,
        1 => colors.auroraB,
        _ => colors.auroraC,
      };
      final alpha = (dark ? .20 : .11) * (1 - index * .08);
      final shader = RadialGradient(
        colors: [
          color.withValues(alpha: alpha),
          color.withValues(alpha: alpha * .42),
          color.withValues(alpha: 0),
        ],
        stops: const [0, .48, 1],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: radius));
      canvas.drawCircle(
        Offset(cx, cy),
        radius,
        Paint()
          ..shader = shader
          ..blendMode = dark ? BlendMode.plus : BlendMode.srcOver,
      );
    }
    canvas.restore();

    if (dark && quality == AuroraQuality.full) {
      final starPaint = Paint()..color = colors.star;
      for (final star in _stars) {
        final twinkle =
            (math.sin(time * (.5 + star.phase) + star.phase * 6) + 1) / 2;
        final position = Offset(star.x * size.width, star.y * size.height);
        canvas.drawCircle(
          position,
          .6 + twinkle * .9,
          starPaint..color = colors.star.withValues(alpha: .08 + twinkle * .24),
        );
      }
    }

    if (veil) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              surface.withValues(alpha: dark ? .24 : .1),
              surface.withValues(alpha: 0),
              surface.withValues(alpha: 0),
              surface.withValues(alpha: dark ? .55 : .32),
            ],
            stops: const [0, .22, .62, 1],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter old) =>
      old.time != time ||
      old.dark != dark ||
      old.colors != colors ||
      old.surface != surface ||
      old.quality != quality ||
      old.scrolling != scrolling;
}

class _Blob {
  const _Blob(
    this.x,
    this.y,
    this.radius,
    this.color,
    this.speed,
    this.phase,
    this.layer,
  );
  final double x;
  final double y;
  final double radius;
  final int color;
  final double speed;
  final double phase;
  final int layer;
}

class _Star {
  const _Star(this.x, this.y, this.phase);
  final double x;
  final double y;
  final double phase;
}
