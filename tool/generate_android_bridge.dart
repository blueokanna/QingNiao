import 'dart:io';

Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent;
  final generator = await Process.start(
    'flutter_rust_bridge_codegen',
    ['generate', '--config-file', 'flutter_rust_bridge.yaml'],
    workingDirectory: root.path,
    mode: ProcessStartMode.inheritStdio,
    runInShell: Platform.isWindows,
  );
  final result = await generator.exitCode;
  if (result != 0) {
    exitCode = result;
    return;
  }
  final entrypoint = File('${root.path}/lib/src/rust/frb_generated.dart');
  final source = await entrypoint.readAsString();
  // FRB 2.13 retains this conditional import even when web generation is disabled.
  final conditional = RegExp(
    r"import 'frb_generated.io.dart'\s+if \(dart.library.js_interop\) 'frb_generated.web.dart';",
  );
  if (!conditional.hasMatch(source) &&
      !source.contains("import 'frb_generated.io.dart';")) {
    throw StateError(
      'Unexpected bridge entrypoint; review the generator output.',
    );
  }
  await entrypoint.writeAsString(
    source.replaceAll(conditional, "import 'frb_generated.io.dart';"),
  );
  final web = File('${root.path}/lib/src/rust/frb_generated.web.dart');
  if (await web.exists()) await web.delete();
}
