import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

import '../lib/source_graph.dart';

class PropertyProbe extends RecursiveAstVisitor<void> {
  final rows = <List<String>>[];

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.name == 'value') {
      rows.add([
        for (final element in propertyReferenceElements(node))
          if (element is GetterElement)
            'getter'
          else if (element is SetterElement)
            'setter'
          else
            element.runtimeType.toString(),
      ]);
    }
    super.visitSimpleIdentifier(node);
  }
}

Future<void> main(List<String> args) async {
  final path = File(args.single).absolute.path;
  final collection = AnalysisContextCollection(includedPaths: [path]);
  try {
    final result = await collection.contexts.single.currentSession
        .getResolvedUnit(path);
    if (result is! ResolvedUnitResult) {
      throw StateError('Expected a resolved, valid property probe');
    }
    final probe = PropertyProbe();
    result.unit.accept(probe);
    stdout.writeln(jsonEncode(probe.rows));
  } finally {
    await collection.dispose();
  }
}
