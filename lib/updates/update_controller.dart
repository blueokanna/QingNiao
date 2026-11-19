import 'dart:async';

import 'package:flutter/material.dart';

import '../messaging/message_repository.dart';

class UpdateRelease {
  const UpdateRelease({
    required this.versionName,
    required this.versionCode,
    required this.size,
    required this.pageUrl,
    required this.notes,
  });

  final String versionName;
  final int versionCode;
  final int size;
  final String pageUrl;
  final String notes;

  factory UpdateRelease.fromMap(Map<dynamic, dynamic> value) => UpdateRelease(
    versionName: value['versionName'] as String,
    versionCode: (value['versionCode'] as num).toInt(),
    size: (value['size'] as num).toInt(),
    pageUrl: value['pageUrl'] as String,
    notes: value['notes'] as String? ?? '',
  );
}

/// One foreground scheduler for the entire app; downloading stays in native I/O.
class UpdateController extends ChangeNotifier with WidgetsBindingObserver {
  UpdateController(this.repository);

  static const checkInterval = Duration(minutes: 5);

  final MessageRepository repository;
  String versionName = '';
  int versionCode = 0;
  String phase = 'idle';
  int received = 0;
  DateTime? lastChecked;
  String? error;
  UpdateRelease? release;
  bool canInstall = false;
  bool automatic = true;
  bool _disposed = false;
  bool _foreground = true;
  bool _started = false;
  bool _preferencesLoaded = false;
  bool _reading = false;
  Timer? _poll;
  Timer? _periodic;
  DateTime? _lastAttempt;

  bool get busy =>
      const {'checking', 'downloading', 'verifying'}.contains(phase);
  double? get progress {
    final size = release?.size ?? 0;
    return size > 0 ? (received / size).clamp(0, 1) : null;
  }

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    try {
      automatic =
          (await repository.settingsAll())['automaticUpdates'] != 'false';
    } catch (_) {}
    if (_disposed) return;
    _preferencesLoaded = true;
    await refresh();
    if (_disposed) return;
    await checkAutomatically();
    _schedule();
  }

  void _schedule() {
    _periodic?.cancel();
    _periodic = null;
    if (!_disposed && _preferencesLoaded && _foreground && automatic && !busy) {
      _periodic = Timer(_remainingInterval, check);
    }
  }

  Duration get _remainingInterval {
    final previous = _lastAttempt ?? lastChecked;
    if (previous == null) return Duration.zero;
    final interval = error == 'check_failed'
        ? const Duration(minutes: 30)
        : checkInterval;
    final elapsed = DateTime.now().difference(previous);
    return elapsed.isNegative || elapsed >= interval
        ? Duration.zero
        : interval - elapsed;
  }

  Future<void> setAutomatic(bool value) async {
    automatic = value;
    _schedule();
    notifyListeners();
    try {
      await repository.settingsSet('automaticUpdates', '$value');
    } catch (_) {
      if (!_disposed) {
        automatic = !value;
        error = 'settings_failed';
        _schedule();
        notifyListeners();
      }
    }
    if (value && automatic && !_disposed) await checkAutomatically();
  }

  Future<void> checkAutomatically() async {
    if (_disposed ||
        !_preferencesLoaded ||
        !_foreground ||
        !automatic ||
        busy) {
      return;
    }
    if (_remainingInterval > Duration.zero) return;
    await check();
  }

  Future<void> check() async {
    if (_disposed || busy) return;
    _periodic?.cancel();
    _lastAttempt = DateTime.now();
    await _command('checkForUpdate');
    _schedule();
  }

  Future<void> download() => _command('downloadUpdate');

  Future<void> install() async {
    if (_disposed) return;
    try {
      if (!canInstall) {
        await repository.invoke<void>('openUpdateInstallSettings');
      } else {
        await repository.invoke<void>('installUpdate');
      }
    } catch (_) {
      await refresh();
      if (!_disposed) {
        error ??= 'install_failed';
        notifyListeners();
      }
    }
  }

  Future<void> _command(String method) async {
    try {
      final value = await repository.invoke<Map>(method);
      if (!_disposed && value != null) _apply(value);
    } catch (_) {
      if (!_disposed) {
        error = 'service_failed';
        if (busy && _foreground) {
          _poll?.cancel();
          _poll = Timer(const Duration(seconds: 5), refresh);
        }
        notifyListeners();
      }
    }
  }

  Future<void> refresh() async {
    if (_disposed || _reading) return;
    _reading = true;
    try {
      await _command('updateInfo');
    } finally {
      _reading = false;
    }
  }

  void _apply(Map<dynamic, dynamic> value) {
    versionName = value['versionName'] as String? ?? '';
    versionCode = (value['versionCode'] as num?)?.toInt() ?? 0;
    phase = value['phase'] as String? ?? 'idle';
    received = (value['received'] as num?)?.toInt() ?? 0;
    final checked = (value['lastChecked'] as num?)?.toInt() ?? 0;
    lastChecked = checked > 0
        ? DateTime.fromMillisecondsSinceEpoch(checked)
        : null;
    error = value['error'] as String?;
    canInstall = value['canInstall'] == true;
    final raw = value['release'];
    release = raw is Map ? UpdateRelease.fromMap(raw) : null;
    _poll?.cancel();
    _poll = null;
    if (busy && _foreground) {
      _poll = Timer(const Duration(milliseconds: 600), refresh);
    }
    _schedule();
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _schedule();
    if (_foreground) {
      unawaited(_resume());
    } else {
      _poll?.cancel();
      _poll = null;
    }
  }

  Future<void> _resume() async {
    if (!_preferencesLoaded) return;
    await refresh();
    await checkAutomatically();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _periodic?.cancel();
    if (_started) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class UpdateScope extends InheritedNotifier<UpdateController> {
  const UpdateScope({
    super.key,
    required UpdateController controller,
    required super.child,
  }) : super(notifier: controller);

  static UpdateController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<UpdateScope>()?.notifier;
}
