// Inspect real Kernel SDK type links and import targets, not generated text.
import 'dart:convert';
import 'dart:io';
import 'package:kernel/kernel.dart';

class _StringLists extends RecursiveVisitor {
  final values = <List<String>>[];
  @override
  void visitListLiteral(ListLiteral node) {
    final strings = <String>[];
    for (final expression in node.expressions) {
      final value = switch (expression) {
        StringLiteral(:final value) => value,
        ConstantExpression(constant: StringConstant(:final value)) => value,
        _ => null,
      };
      if (value == null) return;
      strings.add(value);
    }
    values.add(strings);
    super.visitListLiteral(node);
  }
}

void main(List<String> args) {
  if (args.length != 3) {
    throw ArgumentError('Expected Kernel, entry source, source graph');
  }
  final component = loadComponentFromBinary(args[0]);
  final uri = File(args[1]).absolute.uri;
  final graph = jsonDecode(File(args[2]).readAsStringSync()) as Map;
  final names = <String, String>{
    for (final e in (graph['entities'] as Map).entries)
      e.key as String: (e.value as Map)['name'] as String,
  };
  Object describe(DartType type) {
    if (type is InterfaceType) {
      return {
        'library': type.classNode.enclosingLibrary.importUri.toString(),
        'class': type.classNode.name,
        'arguments': type.typeArguments.map(describe).toList(),
        'nullability': type.nullability.name,
      };
    }
    if (type is FunctionType) {
      return {
        'return': describe(type.returnType),
        'positional': type.positionalParameters.map(describe).toList(),
        'required_count': type.requiredParameterCount,
        'named': {
          for (final p in type.namedParameters) p.name: describe(p.type),
        },
      };
    }
    return type.toString();
  }

  final library = component.libraries.singleWhere((l) => l.fileUri == uri);
  final stringLists = _StringLists();
  library.accept(stringLists);
  stdout.writeln(
    jsonEncode({
      'imports': [
        for (final d in library.dependencies)
          d.targetLibrary.importUri.toString(),
      ],
      'string_lists': stringLists.values,
      'constants': {
        for (final field in library.fields)
          if (field.initializer case ConstantExpression(
            constant: StringConstant(value: final value),
          ))
            field.name.text: value,
      },
      'returns': {
        for (final p in library.procedures)
          if (const {
            'main',
            'shade',
            'origin',
            'blender',
            'dataFile',
            'diskValue',
          }.contains(names[p.name.text] ?? p.name.text))
            names[p.name.text] ?? p.name.text: describe(p.function.returnType),
      },
      'sdk_ui_present': component.libraries.any(
        (l) => l.importUri.toString() == 'dart:ui',
      ),
    }),
  );
}
