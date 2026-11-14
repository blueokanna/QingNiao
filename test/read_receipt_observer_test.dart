import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingniao/messaging/read_receipt_observer.dart';

void main() {
  for (final enabled in [true, false]) {
    testWidgets('visible code acknowledgement enabled=$enabled', (
      tester,
    ) async {
      var reads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                ReadReceiptObserver(
                  enabled: enabled,
                  onRead: () async {
                    reads++;
                  },
                  child: const SizedBox(height: 80),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(reads, 0);
      await tester.pump(const Duration(seconds: 2));
      expect(reads, enabled ? 1 : 0);
      await tester.pump(const Duration(seconds: 3));
      expect(reads, enabled ? 1 : 0);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('partially visible code is not acknowledged', (tester) async {
    var reads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 100,
            child: ListView(
              children: [
                ReadReceiptObserver(
                  enabled: true,
                  onRead: () async {
                    reads++;
                  },
                  child: const SizedBox(height: 200),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 4));
    expect(reads, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
