import 'dart:math' as math;

import 'package:flutter/material.dart';

abstract final class AuroraMotion {
  static const fast = Duration(milliseconds: 160);
  static const base = Duration(milliseconds: 280);
  static const slow = Duration(milliseconds: 420);
  static const morph = Duration(milliseconds: 560);
  static const reveal = Duration(milliseconds: 520);

  static const emphasized = Cubic(.2, 0, 0, 1);
  static const standard = Cubic(.2, 0, .2, 1);
  static const decelerate = Cubic(.05, .7, .1, 1);
  static const accelerate = Cubic(.3, 0, .8, .15);
  static const expressive = Cubic(.34, 1.56, .64, 1);

  static const page = Duration(milliseconds: 380);
  static const sheet = Duration(milliseconds: 420);
  static const snack = Duration(milliseconds: 320);

  static const spring = SpringDescription(mass: 1, stiffness: 320, damping: 26);
  static const bouncy = SpringDescription(mass: 1, stiffness: 260, damping: 18);

  static double stagger(int index, {double step = .045, double max = .32}) {
    return math.min(index * step, max);
  }
}

class AuroraPageTransitionsTheme extends PageTransitionsTheme {
  AuroraPageTransitionsTheme()
    : super(
        builders: const <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      );
}

class AuroraPageTransitionsBuilder extends PageTransitionsBuilder {
  const AuroraPageTransitionsBuilder();

  @override
  Duration get transitionDuration => AuroraMotion.page;

  @override
  Duration get reverseTransitionDuration => AuroraMotion.page;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final enter = CurvedAnimation(
      parent: animation,
      curve: AuroraMotion.decelerate,
      reverseCurve: AuroraMotion.accelerate,
    );
    final exit = CurvedAnimation(
      parent: secondaryAnimation,
      curve: AuroraMotion.standard,
      reverseCurve: AuroraMotion.standard,
    );
    return SlideTransition(
      position: exit.drive(Tween(begin: Offset.zero, end: const Offset(-.12, 0))),
      child: FadeTransition(
        opacity: exit.drive(Tween(begin: 1, end: .6)),
        child: SlideTransition(
          position: enter.drive(Tween(begin: const Offset(.14, 0), end: Offset.zero)),
          child: FadeTransition(
            opacity: enter.drive(Tween(begin: 0, end: 1)),
            child: ScaleTransition(
              scale: enter.drive(Tween(begin: .985, end: 1)),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class AuroraSwitcher extends StatelessWidget {
  const AuroraSwitcher({
    super.key,
    required this.child,
    this.duration = AuroraMotion.base,
    this.axis = Axis.vertical,
    this.alignment = Alignment.center,
  });

  final Widget child;
  final Duration duration;
  final Axis axis;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final begin = axis == Axis.vertical ? const Offset(0, .035) : const Offset(.04, 0);
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: AuroraMotion.decelerate,
      switchOutCurve: AuroraMotion.accelerate,
      layoutBuilder: (current, previous) => Stack(
        alignment: alignment,
        children: [...previous, if (current != null) current],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: animation.drive(Tween(begin: begin, end: Offset.zero)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class AuroraReveal extends StatelessWidget {
  const AuroraReveal({
    super.key,
    required this.index,
    required this.child,
    this.offset = 18,
    this.delay = true,
  });

  final int index;
  final Widget child;
  final double offset;
  final bool delay;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final extra = delay ? (math.min(index, 9) * 38) : 0;
    final duration = AuroraMotion.reveal + Duration(milliseconds: extra);
    final start = extra / duration.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Interval(start.clamp(0, .72), 1, curve: AuroraMotion.decelerate),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * offset),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class AuroraCounter extends StatelessWidget {
  const AuroraCounter({
    super.key,
    required this.value,
    this.style,
    this.duration = AuroraMotion.base,
  });

  final int value;
  final TextStyle? style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return Text('$value', style: style);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: AuroraMotion.decelerate,
      builder: (context, animated, _) => Text(
        '${animated.round()}',
        style: style?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      ),
    );
  }
}

class AuroraParallax extends StatelessWidget {
  const AuroraParallax({
    super.key,
    required this.controller,
    required this.child,
    this.factor = .18,
    this.max,
  });

  final ScrollController controller;
  final Widget child;
  final double factor;
  final double? max;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, child) {
        final offset =
            controller.hasClients ? controller.offset.clamp(0.0, max ?? double.infinity) : 0.0;
        return Transform.translate(offset: Offset(0, -offset * factor), child: child);
      },
    );
  }
}
