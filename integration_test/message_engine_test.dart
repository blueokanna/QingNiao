import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:qingniao/src/rust/api/message_analysis.dart';
import 'package:qingniao/src/rust/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native Rust bridge preserves Unicode and leading zeroes', (
    _,
  ) async {
    await RustLib.init();
    final insights = await analyzeMessages(
      bodies: [
        '\u9a8c\u8bc1\u7801 004321，\u8bf7\u52ff\u8f6c\u53d1',
        '\u660e\u5929\u89c1🌿',
      ],
    );
    expect(insights.first.verificationCode, '004321');
    expect(insights.last.category, 'personal');
    expect(insights.last.verificationCode, isNull);
  });
}
