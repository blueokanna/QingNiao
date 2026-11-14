import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Requires continuous full visibility before acknowledging an incoming code.
class ReadReceiptObserver extends StatefulWidget {
  const ReadReceiptObserver({
    super.key,
    required this.enabled,
    required this.onRead,
    required this.child,
  });
  final bool enabled;
  final Future<void> Function() onRead;
  final Widget child;

  @override
  State<ReadReceiptObserver> createState() => _ReadReceiptObserverState();
}

class _ReadReceiptObserverState extends State<ReadReceiptObserver>
    with WidgetsBindingObserver {
  Timer? _timer;
  int _visibleTicks = 0;
  bool _completed = false;
  ScrollPosition? _position;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _configure();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _position) {
      _position?.removeListener(_resetVisibility);
      _position = position;
      _position?.addListener(_resetVisibility);
    }
  }

  void _resetVisibility() => _visibleTicks = 0;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _resetVisibility();

  @override
  void didUpdateWidget(ReadReceiptObserver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) _configure();
  }

  void _configure() {
    _timer?.cancel();
    _visibleTicks = 0;
    if (widget.enabled && !_completed) {
      _timer = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => _check(),
      );
    }
  }

  void _check() {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    final box = context.findRenderObject();
    final viewport = context.findAncestorRenderObjectOfType<RenderViewport>();
    var visible =
        ModalRoute.of(context)?.isCurrent == true &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed);
    if (box is RenderBox &&
        box.attached &&
        box.hasSize &&
        viewport != null &&
        viewport.hasSize) {
      final top = box.localToGlobal(Offset.zero, ancestor: viewport);
      final rect = top & box.size;
      visible =
          visible &&
          rect.width > 0 &&
          rect.height > 0 &&
          rect.left >= 0 &&
          rect.top >= 0 &&
          rect.right <= viewport.size.width &&
          rect.bottom <= viewport.size.height;
    } else {
      visible = false;
    }
    if (!visible) {
      _visibleTicks = 0;
      return;
    }
    if (++_visibleTicks < 9) return;
    _completed = true;
    _timer?.cancel();
    unawaited(widget.onRead());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _position?.removeListener(_resetVisibility);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
