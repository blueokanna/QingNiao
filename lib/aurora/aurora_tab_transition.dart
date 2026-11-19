import 'package:flutter/material.dart';

import 'aurora_engine.dart';
import 'aurora_motion.dart';

class AuroraTabTransition extends StatefulWidget {
  const AuroraTabTransition({
    super.key,
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  State<AuroraTabTransition> createState() => _AuroraTabTransitionState();
}

class _AuroraTabTransitionState extends State<AuroraTabTransition> {
  late final _springs = List.generate(
    widget.children.length,
    (index) => AuroraEngine.instance.spring(
      value: index == widget.index ? 1 : 0,
      stiffness: 380,
      dampingRatio: 1,
    ),
  );
  late final Set<int> _visited = {widget.index};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AuroraMotion.isReduced(context) ||
        !TickerMode.valuesOf(context).enabled) {
      for (var i = 0; i < _springs.length; i++) {
        _springs[i].jumpTo(i == widget.index ? 1 : 0);
      }
    }
  }

  @override
  void didUpdateWidget(AuroraTabTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(widget.children.length == _springs.length);
    if (oldWidget.index == widget.index) return;
    _visited.add(widget.index);
    final reduce = AuroraMotion.isReduced(context) ||
        !TickerMode.valuesOf(context).enabled;
    for (var i = 0; i < _springs.length; i++) {
      final target = i == widget.index ? 1.0 : 0.0;
      if (reduce) {
        _springs[i].jumpTo(target);
      } else {
        _springs[i].animateTo(target);
      }
    }
  }

  @override
  void dispose() {
    for (final spring in _springs) {
      AuroraEngine.instance.releaseSpring(spring);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRect(
    child: Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          if (_visited.contains(i))
            AnimatedBuilder(
              key: ValueKey(i),
              animation: _springs[i],
              child: RepaintBoundary(
                child: ExcludeFocus(
                  excluding: i != widget.index,
                  child: TickerMode(
                    enabled: i == widget.index,
                    child: widget.children[i],
                  ),
                ),
              ),
              builder: (context, child) {
                final progress = _springs[i].value.clamp(0.0, 1.0);
                // Release inactive page elements and their listeners after exit.
                if (progress == 0 && i != widget.index) {
                  return const SizedBox.shrink();
                }
                return Offstage(
                  offstage: progress == 0 && i != widget.index,
                  child: IgnorePointer(
                    ignoring: i != widget.index,
                    child: ExcludeSemantics(
                      excluding: i != widget.index,
                      child: Opacity(
                        opacity: progress,
                        child: Transform.translate(
                          offset: Offset(0, 16 * (1 - progress)),
                          child: child,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
      ],
    ),
  );
}
