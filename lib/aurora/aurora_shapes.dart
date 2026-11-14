import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:material_new_shapes/material_new_shapes.dart';

import 'aurora_engine.dart';
import 'aurora_theme.dart';

/// Material 3 Expressive 形状库（AndroidX graphics-shapes 的 Flutter 实现）。
///
/// 头像、FAB、导航指示器与徽章使用同一套形状语言，并在状态变化时
/// 通过 [Morph] 连续形变，而不是硬切图标。
abstract final class AuroraShapes {
  static final List<RoundedPolygon> avatars = [
    MaterialShapes.cookie9Sided,
    MaterialShapes.clover4Leaf,
    MaterialShapes.sunny,
    MaterialShapes.gem,
    MaterialShapes.flower,
    MaterialShapes.puffyDiamond,
    MaterialShapes.softBurst,
    MaterialShapes.bun,
    MaterialShapes.cookie6Sided,
    MaterialShapes.oval,
  ];

  static final RoundedPolygon fab = MaterialShapes.sunny;
  static final RoundedPolygon nav = MaterialShapes.cookie9Sided;
  static final RoundedPolygon pill = MaterialShapes.pill;
  static final RoundedPolygon burst = MaterialShapes.softBurst;
  static final RoundedPolygon bloom = MaterialShapes.clover8Leaf;

  static RoundedPolygon forKey(String key) {
    if (key.isEmpty) return MaterialShapes.cookie9Sided;
    var hash = 0;
    for (final unit in key.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return avatars[hash % avatars.length];
  }

  static final Map<int, Morph> _morphs = {};

  static Morph morph(RoundedPolygon from, RoundedPolygon to) {
    final key = Object.hash(identityHashCode(from), identityHashCode(to));
    return _morphs.putIfAbsent(key, () => Morph(from, to));
  }

  static Path path(RoundedPolygon polygon, Size size) {
    final path = polygon.toPath();
    return path.transform(Matrix4.diagonal3Values(size.width, size.height, 1).storage);
  }

  static Path rotatedPath(RoundedPolygon polygon, Size size, double rotate) {
    var result = path(polygon, size);
    if (rotate == 0) return result;
    final c = Offset(size.width / 2, size.height / 2);
    return result.transform(
      Matrix4.translationValues(c.dx, c.dy, 0)
          .multiplied(Matrix4.rotationZ(rotate))
          .multiplied(Matrix4.translationValues(-c.dx, -c.dy, 0))
          .storage,
    );
  }
}

/// 圆形/超椭圆/饼干形头像。首次进入时形状由地址稳定决定。
class AuroraAvatar extends StatelessWidget {
  const AuroraAvatar({
    super.key,
    required this.seed,
    this.size = 52,
    this.label,
    this.icon,
    this.unread = false,
    this.heroTag,
    this.onTap,
    this.glow = false,
  });

  final String seed;
  final double size;
  final String? label;
  final IconData? icon;
  final bool unread;
  final Object? heroTag;
  final VoidCallback? onTap;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final aurora = Theme.of(context).extension<AuroraColors>() ?? _fallback;
    final base = AuroraShapes.forKey(seed);
    final active = unread ? MaterialShapes.sunny : base;
    final initials = _initials(label, seed);
    final bright = Theme.of(context).brightness == Brightness.dark;

    Widget avatar = CustomPaint(
      painter: _ShapeAvatarPainter(
        start: base,
        end: active,
        progress: unread ? 1 : 0,
        colors: [
          Color.alphaBlend(colors.primary.withValues(alpha: bright ? .34 : .16), colors.surface),
          Color.alphaBlend(
            colors.tertiary.withValues(alpha: bright ? .24 : .12),
            colors.surfaceContainerHigh,
          ),
        ],
        ring: aurora.hairline,
        glow: glow ? aurora.glow : null,
      ),
      child: SizedBox(
        width: size,
        height: size,
        child: Center(
          child: icon != null
              ? Icon(icon, size: size * .4, color: colors.onSurfaceVariant)
              : Text(
                  initials,
                  style: TextStyle(
                    fontSize: size * .3,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.4,
                    color: colors.onSurfaceVariant,
                  ),
                ),
        ),
      ),
    );

    if (onTap != null) {
      avatar = GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: avatar);
    }
    if (heroTag != null) {
      avatar = Hero(
        tag: heroTag!,
        flightShuttleBuilder: (context, animation, direction, fromContext, toContext) =>
            AuroraAvatarFlight(animation: animation, seed: seed, size: size, label: label),
        child: avatar,
      );
    }
    return RepaintBoundary(child: avatar);
  }
}

/// 头像文字：号码取末两位，姓名取首字，服务号取末两位数字。
String _initials(String? label, String seed) {
  final text = (label ?? '').trim();
  final source = text.isEmpty ? seed.trim() : text;
  if (source.isEmpty) return '?';
  final digits = source.replaceAll(RegExp(r'\D'), '');
  final numeric = RegExp(r'^[\d\s+()\-]+$').hasMatch(source);
  if (numeric && digits.isNotEmpty) {
    return digits.length >= 2 ? digits.substring(digits.length - 2) : digits;
  }
  return String.fromCharCode(source.runes.first).toUpperCase();
}

class AuroraAvatarFlight extends StatelessWidget {
  const AuroraAvatarFlight({
    super.key,
    required this.animation,
    required this.seed,
    required this.size,
    this.label,
  });

  final Animation<double> animation;
  final String seed;
  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => AuroraAvatar(seed: seed, size: size, label: label),
    );
  }
}

class _ShapeAvatarPainter extends CustomPainter {
  _ShapeAvatarPainter({
    required this.start,
    required this.end,
    required this.progress,
    required this.colors,
    required this.ring,
    this.glow,
  });

  final RoundedPolygon start;
  final RoundedPolygon end;
  final double progress;
  final List<Color> colors;
  final Color ring;
  final Color? glow;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = AuroraShapes.morph(start, end)
        .toPath(progress: progress, rotationPivotX: .5, rotationPivotY: .5)
        .transform(Matrix4.diagonal3Values(size.width, size.height, 1).storage);
    if (glow != null) {
      canvas.drawPath(
        path,
        Paint()
          ..color = glow!.withValues(alpha: .5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(rect),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = ring,
    );
  }

  @override
  bool shouldRepaint(covariant _ShapeAvatarPainter old) =>
      old.start != start ||
      old.end != end ||
      old.progress != progress ||
      old.colors != colors ||
      old.ring != ring ||
      old.glow != glow;
}

/// 以 M3 形状裁切的容器，用于 FAB、导航指示器与强调卡片。
class AuroraShapeContainer extends StatelessWidget {
  const AuroraShapeContainer({
    super.key,
    required this.shape,
    required this.child,
    this.size,
    this.width,
    this.height,
    this.gradient,
    this.color,
    this.border,
    this.glow,
    this.padding = EdgeInsets.zero,
    this.progress = 0,
    this.rotate = 0,
  });

  final RoundedPolygon shape;
  final Widget child;
  final double? size;
  final double? width;
  final double? height;
  final List<Color>? gradient;
  final Color? color;
  final Color? border;
  final Color? glow;
  final EdgeInsets padding;
  final double progress;
  final double rotate;

  @override
  Widget build(BuildContext context) {
    final w = width ?? size;
    final h = height ?? size;
    return RepaintBoundary(
      child: CustomPaint(
        painter: _ContainerPainter(
          shape: shape,
          gradient: gradient,
          color: color,
          border: border,
          glow: glow,
          progress: progress,
          rotate: rotate,
        ),
        child: SizedBox(
          width: w,
          height: h,
          child: Padding(padding: padding, child: Center(child: child)),
        ),
      ),
    );
  }
}

class _ContainerPainter extends CustomPainter {
  _ContainerPainter({
    required this.shape,
    this.gradient,
    this.color,
    this.border,
    this.glow,
    this.progress = 0,
    this.rotate = 0,
  });

  final RoundedPolygon shape;
  final List<Color>? gradient;
  final Color? color;
  final Color? border;
  final Color? glow;
  final double progress;
  final double rotate;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = glow != null ? 3.0 : 0.0;
    final drawSize = Size(size.width - inset * 2, size.height - inset * 2);
    var path = shape
        .toPath()
        .transform(Matrix4.diagonal3Values(drawSize.width, drawSize.height, 1).storage);
    if (rotate != 0) {
      final center = Offset(drawSize.width / 2, drawSize.height / 2);
      path = path.transform(
        Matrix4.translationValues(center.dx, center.dy, 0)
            .multiplied(Matrix4.rotationZ(rotate))
            .multiplied(Matrix4.translationValues(-center.dx, -center.dy, 0))
            .storage,
      );
    }
    canvas.save();
    canvas.translate(inset, inset);
    if (glow != null) {
      canvas.drawPath(
        path,
        Paint()
          ..color = glow!.withValues(alpha: .55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }
    final paint = Paint();
    if (gradient != null) {
      paint.shader = LinearGradient(
        colors: gradient!,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Offset.zero & drawSize);
    } else {
      paint.color = color ?? Colors.white;
    }
    canvas.drawPath(path, paint);
    if (border != null) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = border!,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ContainerPainter old) =>
      old.shape != shape ||
      old.gradient != gradient ||
      old.color != color ||
      old.border != border ||
      old.glow != glow ||
      old.progress != progress ||
      old.rotate != rotate;
}

/// 缓慢呼吸的品牌花朵，用于空状态与引导页。由极光引擎统一时钟驱动，
/// 滚动/省电时自动降频。
class AuroraBloom extends StatefulWidget {
  const AuroraBloom({super.key, this.size = 120, this.static = false});

  final double size;
  final bool static;

  @override
  State<AuroraBloom> createState() => _AuroraBloomState();
}

class _AuroraBloomState extends State<AuroraBloom> {
  late final ValueListenable<double> _clock = AuroraEngine.instance.clock;
  late final RoundedPolygon _shape = AuroraShapes.bloom;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final aurora = Theme.of(context).extension<AuroraColors>() ?? _fallback;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _clock,
        builder: (context, _) {
          final t = AuroraEngine.instance.reduceMotion || widget.static
              ? 0.0
              : _clock.value;
          final path = AuroraShapes.rotatedPath(_shape, Size.square(widget.size), t * .12);
          return CustomPaint(
            size: Size.square(widget.size),
            painter: _BloomPainter(
              path: path,
              phase: t,
              a: aurora.auroraA,
              b: aurora.auroraB,
              surface: colors.surface,
            ),
          );
        },
      ),
    );
  }
}

class _BloomPainter extends CustomPainter {
  _BloomPainter({required this.path, required this.phase, required this.a, required this.b, required this.surface});

  final Path path;
  final double phase;
  final Color a;
  final Color b;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    for (var layer = 0; layer < 3; layer++) {
      final scale = 1 - layer * .17;
      final path = this.path.transform(Matrix4.diagonal3Values(scale, scale, 1).storage);
      final center = size.width / 2;
      canvas.save();
      canvas.translate(center * (1 - scale), center * (1 - scale));
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            colors: [
              a.withValues(alpha: .10 + layer * .05),
              b.withValues(alpha: .08 + layer * .04),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(rect),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .8
          ..color = Color.lerp(a, b, (math.sin(phase + layer) + 1) / 2)!.withValues(alpha: .26),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _BloomPainter old) =>
      old.phase != phase || old.path != path || old.a != a || old.b != b;
}

final AuroraColors _fallback = AuroraColors(  auroraA: const Color(0xFF0E7C6B),
  auroraB: const Color(0xFF5B6CFF),
  auroraC: const Color(0xFF1677A8),
  glow: const Color(0x330E7C6B),
  otp: const Color(0xFF1677A8),
  otpSoft: const Color(0x141677A8),
  success: const Color(0xFF1E7A56),
  warning: const Color(0xFF9A5B00),
  hairline: const Color(0x33FFFFFF),
  glass: const Color(0x14FFFFFF),
  glassStrong: const Color(0x24FFFFFF),
  incomingBubble: const Color(0xFF1C1C1E),
  incomingText: Colors.white,
  outgoingA: const Color(0xFF2A5A4E),
  outgoingB: const Color(0xFF33497A),
  outgoingText: Colors.white,
  navSurface: const Color(0xFF141416),
  star: Colors.white,
);
