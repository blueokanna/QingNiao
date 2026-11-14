import 'dart:ui' as ui;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingniao/aurora/aurora_backdrop.dart';
import 'package:qingniao/aurora/aurora_starfield.dart';
import 'package:qingniao/src/rust/api/starfield.dart';
import 'package:qingniao/src/rust/frb_generated.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;

// A fixed parameter fixture permits GPU regression tests without a host FFI
// toolchain. QINGNIAO_RUST_TEST_LIBRARY exercises the real Rust bridge instead.
Uint8List _parameterFixture() => Uint8List.fromList([
  for (var i = 0; i < 256; i++) ...[
    100,
    150,
    120,
    255,
    100,
    (i * 47) % 256,
    180,
    255,
    160,
    (i * 13) % 256,
    127,
    255,
    (i * 23) % 256,
    (i * 59) % 256,
    i % 4 == 0 ? 0 : 255,
    255,
  ],
]);

void main() {
  testWidgets(
    'Starfield evolves over minutes without visible frame steps or a 12 second reset',
    (tester) async {
      await tester.runAsync(() async {
        final nativeLibrary =
            Platform.environment['QINGNIAO_RUST_TEST_LIBRARY'];
        var parameters = _parameterFixture();
        if (nativeLibrary != null) {
          await RustLib.init(
            externalLibrary: ExternalLibrary.open(nativeLibrary),
          );
          parameters = await createStarfield(seed: 9031);
          expect(parameters, await createStarfield(seed: 9031));
          expect(parameters, isNot(equals(await createStarfield(seed: 9032))));
        }
        final atlas = await AuroraStarfield.decode(parameters);
        final program = await ui.FragmentProgram.fromAsset(
          'shaders/aurora_stars.frag',
        );
        final shader = program.fragmentShader();
        final clock = ValueNotifier(0.0);
        try {
          Future<Uint8List> render(double time) async {
            clock.value = time;
            final recorder = ui.PictureRecorder();
            AuroraGpuStarPainter(
              shader: shader,
              atlas: atlas,
              surface: Colors.black,
              accent: Colors.teal,
              star: Colors.white,
              amoled: true,
              clock: clock,
            ).paint(Canvas(recorder), const Size(240, 480));
            final picture = recorder.endRecording();
            final image = await picture.toImage(240, 480);
            try {
              return (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!.buffer.asUint8List();
            } finally {
              image.dispose();
              picture.dispose();
            }
          }

          final first = await render(0);
          final adjacent = await render(1 / 60);
          final second = await render(120);
          final beforeOldWrap = await render(11.99);
          final afterOldWrap = await render(12.01);
          final late = await render(1800);
          final lateAdjacent = await render(1800 + 1 / 60);
          var lit = 0, changed = 0;
          for (var i = 0; i < first.length; i += 4) {
            if (first[i] > 0) lit++;
            if (first[i] != second[i]) changed++;
            expect(first[i + 3], 255);
            for (var channel = 0; channel < 3; channel++) {
              final offset = i + channel;
              expect(
                (first[offset] - adjacent[offset]).abs(),
                lessThanOrEqualTo(1),
              );
              expect(
                (beforeOldWrap[offset] - afterOldWrap[offset]).abs(),
                lessThanOrEqualTo(1),
              );
              expect(
                (late[offset] - lateAdjacent[offset]).abs(),
                lessThanOrEqualTo(1),
              );
            }
          }
          expect(lit, greaterThan(10));
          expect(lit, lessThan(240 * 480 * .03));
          expect(changed, greaterThan(10));
        } finally {
          shader.dispose();
          atlas.dispose();
          clock.dispose();
          if (nativeLibrary != null) RustLib.dispose();
        }
      });
    },
  );
  test('Parameter texture rejects truncated and transparent data', () async {
    await expectLater(
      AuroraStarfield.decode(Uint8List(4)),
      throwsFormatException,
    );
    await expectLater(
      AuroraStarfield.decode(Uint8List(4096)),
      throwsFormatException,
    );
  });
}
