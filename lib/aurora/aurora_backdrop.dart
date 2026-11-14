import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/app_settings.dart';
import 'aurora_engine.dart';
import 'aurora_starfield.dart';

class AuroraBackdrop extends StatefulWidget {
  const AuroraBackdrop({super.key, this.veil = true});
  final bool veil;

  @override
  State<AuroraBackdrop> createState() => _AuroraBackdropState();
}

class _AuroraBackdropState extends State<AuroraBackdrop> {
  ui.FragmentShader? _shader;
  bool _wasAnimating = true;
  double _frozenTime = 0;
  double _timeOffset = 0;

  @override
  void initState() {
    super.initState();
    // Resources are prepared before runApp: no temporary sky that jumps on load.
    _shader = AuroraStarfield.program?.fragmentShader();
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final settings = AppScope.maybeOf(context);
    final amoled =
        scheme.brightness == Brightness.dark && settings?.amoled == true;
    final animate =
        !MediaQuery.disableAnimationsOf(context) &&
        !AuroraEngine.instance.reduceMotion &&
        settings?.lowPowerAurora != true;
    final now = AuroraEngine.instance.clock.value;
    if (!animate && _wasAnimating) {
      _frozenTime = now - _timeOffset;
    } else if (animate && !_wasAnimating) {
      _timeOffset = now - _frozenTime;
    }
    _wasAnimating = animate;
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _shader != null
            ? AuroraGpuStarPainter(
                shader: _shader!,
                atlas: AuroraStarfield.atlas!,
                surface: amoled ? Colors.black : scheme.surface,
                accent: scheme.primary,
                star: amoled
                    ? const Color(0xffb8c9c6)
                    : scheme.onSurfaceVariant,
                amoled: amoled,
                clock: animate ? AuroraEngine.instance.clock : null,
                frozenTime: _frozenTime,
                timeOffset: _timeOffset,
              )
            : AuroraStarPainter(
                surface: amoled ? Colors.black : scheme.surface,
                accent: scheme.primary,
                star: amoled
                    ? const Color(0xffb8c9c6)
                    : scheme.onSurfaceVariant,
                amoled: amoled,
              ),
      ),
    );
  }
}

/// GPU fragment shading: one draw, one shared clock, no CPU particle updates.
class AuroraGpuStarPainter extends CustomPainter {
  AuroraGpuStarPainter({
    required this.shader,
    required this.atlas,
    required this.surface,
    required this.accent,
    required this.star,
    required this.amoled,
    this.clock,
    this.frozenTime = 0,
    this.timeOffset = 0,
  }) : super(repaint: clock) {
    shader.setImageSampler(0, atlas);
    _paint = Paint()..shader = shader;
  }

  final ui.FragmentShader shader;
  final ui.Image atlas;
  final Color surface, accent, star;
  final bool amoled;
  final ValueListenable<double>? clock;
  final double frozenTime, timeOffset;
  late final Paint _paint;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, clock == null ? frozenTime : clock!.value - timeOffset);
    var index = 3;
    for (final color in [surface, accent, star]) {
      shader.setFloat(index++, color.r);
      shader.setFloat(index++, color.g);
      shader.setFloat(index++, color.b);
    }
    shader.setFloat(12, amoled ? 1 : 0);
    canvas.drawRect(Offset.zero & size, _paint);
  }

  @override
  bool shouldRepaint(covariant AuroraGpuStarPainter old) =>
      old.shader != shader ||
      old.atlas != atlas ||
      old.surface != surface ||
      old.accent != accent ||
      old.star != star ||
      old.amoled != amoled ||
      old.frozenTime != frozenTime ||
      old.timeOffset != timeOffset ||
      old.clock != clock;
}

/// Static fallback for unavailable Rust/GPU resources. Never flashes on failure.
class AuroraStarPainter extends CustomPainter {
  AuroraStarPainter({
    required this.surface,
    required this.accent,
    required this.star,
    required this.amoled,
  });
  final Color surface;
  final Color accent;
  final Color star;
  final bool amoled;
  static final _stars = List.generate(48, (i) {
    final random = math.Random(9031 + i * 97);
    return (random.nextDouble(), random.nextDouble(), random.nextDouble());
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = surface);
    if (!amoled) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-.8, -.9),
            radius: 1.4,
            colors: [
              accent.withValues(alpha: .12),
              accent.withValues(alpha: 0),
            ],
          ).createShader(rect),
      );
    }
    final paint = Paint();
    for (final (x, y, phase) in _stars) {
      paint.color = star.withValues(alpha: (amoled ? .18 : .1) + phase * .18);
      canvas.drawCircle(
        Offset(x * size.width, y * size.height),
        .65 + phase * .65,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant AuroraStarPainter old) =>
      old.surface != surface ||
      old.accent != accent ||
      old.star != star ||
      old.amoled != amoled;
}

class AuroraBackdropScope extends InheritedWidget {
  const AuroraBackdropScope({super.key, required super.child});
  static bool exists(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AuroraBackdropScope>() != null;
  @override
  bool updateShouldNotify(AuroraBackdropScope oldWidget) => false;
}
