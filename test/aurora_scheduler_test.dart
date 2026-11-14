import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:qingniao/aurora/aurora_engine.dart';
import 'package:qingniao/aurora/aurora_motion.dart';

void main() {
  testWidgets(
    'app reduced motion bypasses reveal, switch and counter animations',
    (tester) async {
      final engine = AuroraEngine.instance;
      engine.configure(
        motion: AuroraMotionLevel.reduced,
        reduce: false,
        backdrop: false,
      );
      addTearDown(
        () => engine.configure(motion: AuroraMotionLevel.full, reduce: false),
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Column(
            children: [
              AuroraReveal(index: 0, child: Text('Visible')),
              AuroraSwitcher(child: Text('Current')),
              AuroraCounter(value: 42),
            ],
          ),
        ),
      );
      expect(find.text('42'), findsOneWidget);
      expect(find.byType(AnimatedSwitcher), findsNothing);
      expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'long frames preserve elapsed spring time and retarget continuity',
    (tester) async {
      final engine = AuroraEngine.instance;
      engine.configure(
        motion: AuroraMotionLevel.full,
        reduce: false,
        backdrop: false,
      );
      engine.resume();
      engine.setRefreshRate(120);
      engine.attach(tester);
      final spring = engine.spring(dampingRatio: 1);
      final reference = AuroraSpring(dampingRatio: 1)..animateTo(1);
      spring.animateTo(1);
      await tester.pump();
      reference.drive(1 / 120);
      await tester.pump(const Duration(milliseconds: 250));
      reference.drive(.25);
      expect(spring.value, closeTo(reference.value, 1e-10));
      final before = spring.value;
      spring.animateTo(0);
      expect(spring.value, before);
      await tester.pump(const Duration(seconds: 2));
      expect(spring.value, 0);
      expect(tester.binding.transientCallbackCount, 0);
      engine.releaseSpring(spring);
      engine.detach();
      reference.dispose();
    },
  );

  testWidgets(
    'removing a later spring during a frame skips its stale snapshot entry',
    (tester) async {
      final engine = AuroraEngine.instance;
      engine.configure(
        motion: AuroraMotionLevel.full,
        reduce: false,
        backdrop: false,
      );
      engine.resume();
      engine.attach(tester);
      final first = engine.spring();
      final second = engine.spring();
      var removed = false;
      first.addListener(() {
        if (!removed) {
          removed = true;
          engine.releaseSpring(second);
        }
      });
      first.animateTo(1);
      second.animateTo(1);
      await tester.pump();
      expect(removed, isTrue);
      expect(tester.takeException(), isNull);
      engine.releaseSpring(first);
      expect(tester.binding.transientCallbackCount, 0);
      engine.detach();
    },
  );
}
