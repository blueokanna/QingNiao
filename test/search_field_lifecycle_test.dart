import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingniao/aurora/aurora_theme.dart';
import 'package:qingniao/aurora/aurora_widgets.dart';
import 'package:qingniao/l10n/app_strings.dart';

void main() {
  setUpAll(AppStrings.initialize);
  testWidgets(
    'Search field follows replacement controllers without taking ownership',
    (tester) async {
      final first = TextEditingController(text: 'First');
      final second = TextEditingController(text: 'Second');
      TextEditingController? current = first;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAuroraTheme(
            brightness: Brightness.light,
            appearance: const AuroraAppearance(),
          ),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return AuroraSearchField(
                  controller: current,
                  hintText: 'Search',
                );
              },
            ),
          ),
        ),
      );
      expect(find.text('First'), findsOneWidget);
      rebuild(() => current = second);
      await tester.pump();
      expect(find.text('Second'), findsOneWidget);
      first.text = 'Detached';
      await tester.pump();
      expect(find.text('Detached'), findsNothing);
      rebuild(() => current = null);
      await tester.pump();
      expect(find.text('Second'), findsOneWidget);
      second.text = 'Still externally owned';
      await tester.pump();
      expect(find.text('Still externally owned'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      first.text = 'Usable after unmount';
      second.text = 'Usable after unmount';
      expect(tester.takeException(), isNull);
      first.dispose();
      second.dispose();
    },
  );
}
