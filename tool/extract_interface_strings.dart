import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

class InterfaceVisitor extends RecursiveAstVisitor<void> {
  InterfaceVisitor(this.path);
  final String path;
  final records = <Map<String, dynamic>>[];
  void record(StringLiteral node, String text, List<String> arguments) {
    if (!RegExp(r'[\u3400-\u9fff]').hasMatch(text)) return;
    final constants = <Map<String, dynamic>>[];
    bool restricted = false;
    for (
      AstNode? parent = node.parent;
      parent != null;
      parent = parent.parent
    ) {
      if (parent is FormalParameter || parent is ConstantPattern) {
        restricted = true;
      }
      if (parent is InstanceCreationExpression &&
          parent.keyword?.lexeme == 'const') {
        constants.add({
          'offset': parent.keyword!.offset,
          'length': 5,
          'value': '',
        });
      }
      if (parent is TypedLiteral && parent.constKeyword != null) {
        constants.add({
          'offset': parent.constKeyword!.offset,
          'length': 5,
          'value': '',
        });
      }
      if (parent is VariableDeclarationList &&
          parent.keyword?.lexeme == 'const') {
        constants.add({
          'offset': parent.keyword!.offset,
          'length': 5,
          'value': 'final',
        });
      }
    }
    records.add({
      'path': path,
      'offset': node.offset,
      'length': node.length,
      'text': text,
      'arguments': arguments,
      'restricted': restricted,
      'constants': constants,
    });
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) =>
      record(node, node.value, []);
  @override
  void visitStringInterpolation(StringInterpolation node) {
    final arguments = <String>[];
    final text = StringBuffer();
    for (final element in node.elements) {
      if (element is InterpolationString) text.write(element.value);
      if (element is InterpolationExpression) {
        text.write('{p${arguments.length}}');
        arguments.add(element.expression.toSource());
      }
    }
    record(node, text.toString(), arguments);
  }
}

void main() {
  final records = <Map<String, dynamic>>[];
  for (final file in Directory(
    'lib',
  ).listSync(recursive: true).whereType<File>()) {
    final path = file.path.replaceAll('\\', '/');
    if (!path.endsWith('.dart') ||
        path.contains('/src/rust/') ||
        path.endsWith('demo_repository.dart')) {
      continue;
    }
    final visitor = InterfaceVisitor(path);
    parseString(
      content: file.readAsStringSync(),
      throwIfDiagnostics: false,
    ).unit.accept(visitor);
    records.addAll(visitor.records);
  }
  File('build/pantone/interface-strings.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(records));
  stdout.writeln('${records.length} interface string occurrences');
}
