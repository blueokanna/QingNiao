import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

class TranslationCalls extends RecursiveAstVisitor<void> {
  final keys = <String>{};

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'tr' &&
        node.argumentList.arguments.isNotEmpty) {
      final first = node.argumentList.arguments.first;
      if (first is StringLiteral && first.stringValue != null) {
        keys.add(first.stringValue!);
      }
    }
    super.visitMethodInvocation(node);
  }
}

void main() {
  final errors = <String>[];
  final catalogs = <String, Map<String, dynamic>>{};
  for (final file in Directory('assets/l10n').listSync().whereType<File>()) {
    if (!file.path.endsWith('.json')) continue;
    final code = file.uri.pathSegments.last.split('.').first;
    catalogs[code] =
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }
  final source = catalogs['en']!;
  final placeholders = RegExp(r'\{p\d+\}');
  List<String> parameters(String text) =>
      placeholders.allMatches(text).map((m) => m[0]!).toList()..sort();
  for (final entry in catalogs.entries) {
    final missing = source.keys.toSet().difference(entry.value.keys.toSet());
    final extra = entry.value.keys.toSet().difference(source.keys.toSet());
    if (missing.isNotEmpty) errors.add('${entry.key}: missing $missing');
    if (extra.isNotEmpty) errors.add('${entry.key}: unknown $extra');
    for (final value in entry.value.entries) {
      if (value.value is! String || (value.value as String).trim().isEmpty) {
        errors.add('${entry.key}: empty or invalid ${value.key}');
      } else if (parameters(value.key).join(',') !=
          parameters(value.value as String).join(',')) {
        errors.add('${entry.key}: placeholder mismatch ${value.key}');
      }
    }
  }
  final calls = TranslationCalls();
  final han = RegExp(r'[\u3400-\u9fff\u{20000}-\u{323af}]', unicode: true);
  for (final directory in [
    'lib',
    'rust/src',
    'server-rs/src',
    'android/app/src',
  ]) {
    for (final file in Directory(
      directory,
    ).listSync(recursive: true).whereType<File>()) {
      if (!['.dart', '.kt', '.rs'].any(file.path.endsWith)) continue;
      final text = file.readAsStringSync();
      if (han.hasMatch(text)) {
        errors.add('Han character in source: ${file.path}');
      }
      if (file.path.endsWith('.dart')) {
        parseString(
          content: text,
          throwIfDiagnostics: false,
        ).unit.accept(calls);
      }
    }
  }
  for (final key in calls.keys.difference(source.keys.toSet())) {
    errors.add('Unregistered interface text: $key');
  }
  if (errors.isNotEmpty) {
    stderr.writeln(errors.join('\n'));
    exitCode = 1;
  } else {
    stdout.writeln(
      '${catalogs.length} catalogs, ${source.length} entries each; placeholders and source checks passed.',
    );
  }
}
