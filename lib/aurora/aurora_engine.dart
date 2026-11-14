import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// 动效档位。由用户设置，并可被运行时帧耗时自动降级覆盖。
enum AuroraMotionLevel { full, balanced, reduced }

/// 渲染质量。极光引擎根据真实帧耗时自动调整。
enum AuroraQuality { full, balanced, efficient }

/// 一个由极光引擎统一驱动的弹簧。
///
/// 页面中不创建 `AnimationController`，所有按压、指示器、banner 位移
/// 都注册到同一个 [Ticker]，减少 vsync 订阅与对象分配。
class AuroraSpring extends ChangeNotifier {
  AuroraSpring({
    double value = 0,
    this.stiffness = 340,
    this.dampingRatio = 0.78,
  }) : _value = value,
       _target = value;

  final double stiffness;
  final double dampingRatio;

  double _value;
  double _target;
  double _velocity = 0;
  bool _settled = true;

  double get value => _value;
  double get target => _target;
  bool get settled => _settled;

  void animateTo(double target) {
    if ((target - _target).abs() < 0.0005 && _settled) return;
    _target = target;
    _settled = false;
  }

  void jumpTo(double value) {
    _value = value;
    _target = value;
    _velocity = 0;
    if (!_settled) {
      _settled = true;
      notifyListeners();
    }
  }

  void drive(double dt) {
    if (_settled) return;
    final omega = math.sqrt(stiffness);
    final zeta = dampingRatio * 2 * omega;
    final displacement = _value - _target;
    final acceleration = -stiffness * displacement - zeta * _velocity;
    _velocity += acceleration * dt;
    _value += _velocity * dt;
    if ((_value - _target).abs() < 0.0015 && _velocity.abs() < 0.015) {
      _value = _target;
      _velocity = 0;
      _settled = true;
    }
    notifyListeners();
  }
}

/// 极光引擎：全局集中调度与统一渲染。
///
/// * 只持有一个 [Ticker]，驱动所有 [AuroraSpring]；
/// * 极光背景使用被限频的共享时钟，页面切换不会重启时间线；
/// * 通过 [SchedulerBinding.addTimingsCallback] 观察 build/raster 耗时，
///   在卡顿时自动降低背景复杂度与动画频率；
/// * 滚动期间让氛围动效退避，把 GPU 预算留给列表。
class AuroraEngine extends ChangeNotifier {
  AuroraEngine._() {
    _clock = ValueNotifier<double>(0);
  }

  static final AuroraEngine instance = AuroraEngine._();

  late final ValueNotifier<double> _clock;
  ValueListenable<double> get clock => _clock;

  final Set<AuroraSpring> _springs = <AuroraSpring>{};
  final Set<VoidCallback> _qualityListeners = <VoidCallback>{};
  Ticker? _ticker;
  Duration _lastElapsed = Duration.zero;
  double _emitAccumulator = 0;
  double _elapsedSeconds = 0;
  bool _scrolling = false;
  bool _paused = false;
  bool _reduceMotion = false;
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

  /// 背景最低重绘频率：完整 30fps、平衡 24fps、省电 15fps。
  int get backdropFps => switch (_quality) {
    AuroraQuality.full => _motionLevel == AuroraMotionLevel.full ? 30 : 20,
    AuroraQuality.balanced => 24,
    AuroraQuality.efficient => 15,
  };

  int get blobCount => switch (_quality) {
    AuroraQuality.full => 5,
    AuroraQuality.balanced => 3,
    AuroraQuality.efficient => 2,
  };

  bool get allowGrain => _quality == AuroraQuality.full;
  bool get allowParallax => _quality != AuroraQuality.efficient;

  void configure({required AuroraMotionLevel motion, required bool reduce}) {
    final changed = _motionLevel != motion || _reduceMotion != reduce;
    _motionLevel = motion;
    _reduceMotion = reduce;
    if (reduce) {
      for (final spring in _springs) {
        spring.jumpTo(spring.target);
      }
    }
    if (changed) {
      _notifyQuality();
      _clock.value = _clock.value;
    }
  }

  void attach(TickerProvider vsync) {
    if (_ticker != null) return;
    _ticker = vsync.createTicker(_tick)..start();
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
    _lastElapsed = Duration.zero;
    _ticker?.start();
  }

  void setScrolling(bool value) {
    if (_scrolling == value) return;
    _scrolling = value;
  }

  AuroraSpring spring({double value = 0, double stiffness = 340, double dampingRatio = 0.78}) {
    final spring = AuroraSpring(value: value, stiffness: stiffness, dampingRatio: dampingRatio);
    _springs.add(spring);
    return spring;
  }

  void releaseSpring(AuroraSpring spring) {
    _springs.remove(spring);
    spring.dispose();
  }

  void addQualityListener(VoidCallback listener) => _qualityListeners.add(listener);

  void removeQualityListener(VoidCallback listener) => _qualityListeners.remove(listener);

  void _notifyQuality() {
    for (final listener in List<VoidCallback>.of(_qualityListeners)) {
      listener();
    }
    notifyListeners();
  }

  void _tick(Duration elapsed) {
    if (_paused) return;
    final rawDt = _lastElapsed == Duration.zero
        ? 1 / 60
        : (elapsed - _lastElapsed).inMicroseconds / 1000000;
    _lastElapsed = elapsed;
    final dt = rawDt.clamp(0.0, 0.05);
    _elapsedSeconds += dt;

    if (!_reduceMotion) {
      for (final spring in List<AuroraSpring>.of(_springs)) {
        spring.drive(dt);
      }
    }

    // 背景与氛围动效按质量档位限频，避免每帧 rAF 级别的无谓重绘。
    final interval = 1 / (_scrolling ? math.min(backdropFps, 20) : backdropFps);
    _emitAccumulator += dt;
    if (_emitAccumulator >= interval) {
      _emitAccumulator %= interval;
      _clock.value = _elapsedSeconds;
    }
  }

  void _onTimings(List<FrameTiming> timings) {
    if (timings.isEmpty) return;
    var total = 0.0;
    for (final timing in timings) {
      total += timing.totalSpan.inMicroseconds / 1000;
    }
    final sample = total / timings.length;
    _averageFrameMs = _averageFrameMs * 0.82 + sample * 0.18;
    if (!_warmedUp) {
      if (_averageFrameMs < 40) _warmedUp = true;
      return;
    }
    if (_averageFrameMs > 26) {
      _badFrames += timings.length;
      _goodFrames = 0;
      if (_badFrames > 90 && _quality != AuroraQuality.efficient) {
        _quality = AuroraQuality.values[_quality.index + 1];
        _badFrames = 0;
        _notifyQuality();
      }
    } else if (_averageFrameMs < 13) {
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

  /// 调试面板用：手动重置自动画质。
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
