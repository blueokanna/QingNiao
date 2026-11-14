import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

enum AuroraMotionLevel { full, balanced, reduced }

enum AuroraQuality { full, balanced, efficient }

class AuroraSpring extends ChangeNotifier {
  AuroraSpring({
    double value = 0,
    this.stiffness = 340,
    this.dampingRatio = 0.78,
    this.onActivity,
  }) : _value = value,
       _target = value {
    if (!value.isFinite) throw ArgumentError.value(value, 'value');
    if (!stiffness.isFinite || stiffness <= 0) {
      throw ArgumentError.value(stiffness, 'stiffness');
    }
    if (!dampingRatio.isFinite || dampingRatio <= 0) {
      throw ArgumentError.value(dampingRatio, 'dampingRatio');
    }
  }

  final double stiffness;
  final double dampingRatio;
  final VoidCallback? onActivity;

  double _value;
  double _target;
  double _velocity = 0;
  bool _settled = true;

  double get value => _value;
  double get target => _target;
  bool get settled => _settled;

  void animateTo(double target) {
    if (!target.isFinite) throw ArgumentError.value(target, 'target');
    if ((target - _target).abs() < 0.0005 && _settled) return;
    _target = target;
    _settled = false;
    onActivity?.call();
  }

  void jumpTo(double value) {
    if (!value.isFinite) throw ArgumentError.value(value, 'value');
    final changed = _value != value || !_settled;
    _value = value;
    _target = value;
    _velocity = 0;
    _settled = true;
    if (changed) notifyListeners();
  }

  void drive(double dt) {
    if (!dt.isFinite || dt < 0) throw ArgumentError.value(dt, 'dt');
    if (dt == 0) return;
    if (_settled) return;
    final omega = math.sqrt(stiffness);
    final zeta = dampingRatio;
    final displacement = _value - _target;
    if ((zeta - 1).abs() < 0.0001) {
      final coefficient = _velocity + omega * displacement;
      final decay = math.exp(-omega * dt);
      _value = _target + (displacement + coefficient * dt) * decay;
      _velocity =
          (coefficient - omega * (displacement + coefficient * dt)) * decay;
    } else if (zeta < 1) {
      final damped = omega * math.sqrt(1 - zeta * zeta);
      final coefficient = (_velocity + zeta * omega * displacement) / damped;
      final decay = math.exp(-zeta * omega * dt);
      final cosine = math.cos(damped * dt);
      final sine = math.sin(damped * dt);
      final position = displacement * cosine + coefficient * sine;
      _value = _target + decay * position;
      _velocity =
          decay *
          (-zeta * omega * position -
              displacement * damped * sine +
              coefficient * damped * cosine);
    } else {
      final root = math.sqrt(zeta * zeta - 1);
      final first = -omega * (zeta - root);
      final second = -omega * (zeta + root);
      final coefficient =
          (_velocity - second * displacement) / (first - second);
      final other = displacement - coefficient;
      _value =
          _target +
          coefficient * math.exp(first * dt) +
          other * math.exp(second * dt);
      _velocity =
          first * coefficient * math.exp(first * dt) +
          second * other * math.exp(second * dt);
    }
    if ((_value - _target).abs() < 0.0015 && _velocity.abs() < 0.015) {
      _value = _target;
      _velocity = 0;
      _settled = true;
    }
    notifyListeners();
  }
}

/// Coordinates app-owned springs and the backdrop; Flutter owns route tickers.
class AuroraEngine extends ChangeNotifier {
  AuroraEngine._() {
    _clock = ValueNotifier<double>(0);
  }

  static final AuroraEngine instance = AuroraEngine._();

  late final ValueNotifier<double> _clock;
  ValueListenable<double> get clock => _clock;

  final Set<AuroraSpring> _springs = <AuroraSpring>{};
  final Set<AuroraSpring> _activeSprings = <AuroraSpring>{};
  List<AuroraSpring>? _activeSnapshot;
  final Set<VoidCallback> _qualityListeners = <VoidCallback>{};
  Ticker? _ticker;
  Duration? _lastElapsed;
  double _refreshRate = 60;
  double _elapsedSeconds = 0;
  bool _scrolling = false;
  bool _paused = false;
  bool _reduceMotion = false;
  bool _backdropEnabled = true;
  AuroraMotionLevel _motionLevel = AuroraMotionLevel.full;
  AuroraQuality _quality = AuroraQuality.full;
  double _averageFrameMs = 12;
  int _goodFrames = 0;
  int _badFrames = 0;
  bool _warmedUp = false;

  AuroraMotionLevel get motionLevel => _motionLevel;
  AuroraQuality get quality => _quality;
  bool get scrolling => _scrolling;
  bool get paused => _paused;
  bool get reduceMotion => _reduceMotion;
  double get elapsedSeconds => _elapsedSeconds;
  double get averageFrameMs => _averageFrameMs;

  double get refreshRate => _refreshRate;

  void setRefreshRate(double value) {
    if (value.isFinite && value >= 24 && value <= 480) _refreshRate = value;
  }

  int get blobCount => switch (_quality) {
    AuroraQuality.full => 5,
    AuroraQuality.balanced => 3,
    AuroraQuality.efficient => 2,
  };

  bool get allowGrain => _quality == AuroraQuality.full;
  bool get allowParallax => _quality != AuroraQuality.efficient;

  void configure({
    required AuroraMotionLevel motion,
    required bool reduce,
    bool? backdrop,
  }) {
    reduce = reduce || motion == AuroraMotionLevel.reduced;
    final changed = _motionLevel != motion || _reduceMotion != reduce;
    _motionLevel = motion;
    _reduceMotion = reduce;
    if (backdrop != null) _backdropEnabled = backdrop;
    if (reduce) {
      for (final spring in List<AuroraSpring>.of(_springs)) {
        if (!_springs.contains(spring)) continue;
        spring.jumpTo(spring.target);
      }
    }
    if (changed) {
      _notifyQuality();
    }
    _syncTicker();
  }

  void _syncTicker() {
    if (_paused || _ticker == null) return;
    if (_reduceMotion) {
      for (final spring in List<AuroraSpring>.of(_springs)) {
        if (!_springs.contains(spring)) continue;
        spring.jumpTo(spring.target);
      }
      _activeSprings.removeWhere((spring) => spring.settled);
      _activeSnapshot = null;
    }
    final needed =
        !_reduceMotion && (_backdropEnabled || _activeSprings.isNotEmpty);
    if (needed && !_ticker!.isActive) {
      _lastElapsed = null;
      _ticker!.start();
    }
    if (!needed && _ticker!.isActive) _ticker!.stop();
  }

  void attach(TickerProvider vsync) {
    if (_ticker != null) return;
    _ticker = vsync.createTicker(_tick);
    _syncTicker();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void detach() {
    _ticker?.dispose();
    _ticker = null;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
  }

  void pause() {
    if (_paused) return;
    _paused = true;
    _ticker?.stop();
  }

  void resume() {
    if (!_paused) return;
    _paused = false;
    _lastElapsed = null;
    _syncTicker();
  }

  void setScrolling(bool value) {
    if (_scrolling == value) return;
    _scrolling = value;
  }

  AuroraSpring spring({
    double value = 0,
    double stiffness = 340,
    double dampingRatio = 0.78,
  }) {
    late final AuroraSpring spring;
    spring = AuroraSpring(
      value: value,
      stiffness: stiffness,
      dampingRatio: dampingRatio,
      onActivity: () {
        if (_activeSprings.add(spring)) _activeSnapshot = null;
        _syncTicker();
        if (spring.settled && _activeSprings.remove(spring)) {
          _activeSnapshot = null;
        }
      },
    );
    _springs.add(spring);
    return spring;
  }

  void releaseSpring(AuroraSpring spring) {
    _springs.remove(spring);
    if (_activeSprings.remove(spring)) _activeSnapshot = null;
    spring.dispose();
    _syncTicker();
  }

  void addQualityListener(VoidCallback listener) =>
      _qualityListeners.add(listener);

  void removeQualityListener(VoidCallback listener) =>
      _qualityListeners.remove(listener);

  void _notifyQuality() {
    for (final listener in List<VoidCallback>.of(_qualityListeners)) {
      listener();
    }
    notifyListeners();
  }

  void _tick(Duration elapsed) {
    if (_paused) return;
    final rawDt = _lastElapsed == null
        ? 1 / _refreshRate
        : (elapsed - _lastElapsed!).inMicroseconds / 1000000;
    _lastElapsed = elapsed;
    final dt = math.max(0.0, rawDt);
    _elapsedSeconds += dt.clamp(0.0, 0.05);

    if (!_reduceMotion) {
      final active = _activeSnapshot ??= _activeSprings.toList(growable: false);
      for (final spring in active) {
        // A listener can remove another spring while this frame is being delivered.
        if (!_activeSprings.contains(spring)) continue;
        spring.drive(dt);
        if (spring.settled && _activeSprings.remove(spring)) {
          _activeSnapshot = null;
        }
      }
    }

    if (_backdropEnabled &&
        !_reduceMotion &&
        _elapsedSeconds - _clock.value >= 1 / 30) {
      _clock.value = _elapsedSeconds;
    }
    _syncTicker();
  }

  void _onTimings(List<FrameTiming> timings) {
    if (_paused || timings.isEmpty) return;
    var total = 0.0;
    for (final timing in timings) {
      total +=
          math.max(
            timing.buildDuration.inMicroseconds,
            timing.rasterDuration.inMicroseconds,
          ) /
          1000;
    }
    final sample = total / timings.length;
    _averageFrameMs = _averageFrameMs * 0.82 + sample * 0.18;
    if (!_warmedUp) {
      if (_averageFrameMs < 40) _warmedUp = true;
      return;
    }
    final budget = 1000 / _refreshRate;
    if (_averageFrameMs > budget * 1.1) {
      _badFrames += timings.length;
      _goodFrames = 0;
      if (_badFrames > 90 && _quality != AuroraQuality.efficient) {
        _quality = AuroraQuality.values[_quality.index + 1];
        _badFrames = 0;
        _notifyQuality();
      }
    } else if (_averageFrameMs < budget * .7) {
      _goodFrames += timings.length;
      _badFrames = 0;
      if (_goodFrames > 600 && _quality != AuroraQuality.full) {
        _quality = AuroraQuality.values[_quality.index - 1];
        _goodFrames = 0;
        _notifyQuality();
      }
    } else {
      _badFrames = 0;
      _goodFrames = 0;
    }
  }

  void resetQuality() {
    _quality = AuroraQuality.full;
    _badFrames = 0;
    _goodFrames = 0;
    _notifyQuality();
  }

  @override
  void dispose() {
    detach();
    super.dispose();
  }
}
