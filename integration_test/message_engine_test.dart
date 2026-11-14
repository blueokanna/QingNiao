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
      bodies: ['验证码 004321，请勿转发', '明天见🌿'],
    );
    expect(insights.first.verificationCode, '004321');
    expect(insights.last.category, 'personal');
    expect(insights.last.verificationCode, isNull);
  });
}
