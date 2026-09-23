// Read actual Kernel metadata; generated names are mapped back to source names.
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:kernel/kernel.dart';

void main(List<String> args) {
  if (args.length != 3)
    throw ArgumentError('Expected Kernel, source root, source graph');
  final component = loadComponentFromBinary(args[0]);
  final root = Directory(args[1]).absolute.uri.toString();
  final graph = jsonDecode(File(args[2]).readAsStringSync()) as Map;
  final entities = graph['entities'] as Map;
  final names = <String, String>{
    for (final e in entities.entries)
      e.key as String: (e.value as Map)['name'] as String,
  };
  final units = <String, String>{
    for (final uri in (graph['library_language_versions'] as Map).keys)
      'unit_${sha256.convert(utf8.encode(uri as String))}.dart': uri,
  };
  for (final e in (graph['libraries'] as Map).entries) {
    final record = e.value as Map;
    for (final match in RegExp(
      r'\b_[A-Za-z_$][\w$]*',
    ).allMatches(record['source'] as String)) {
      final name = match.group(0)!;
      names['msbEntity_member_${sha256.convert(utf8.encode('${record['owner']}::private::$name'))}'] =
          name;
    }
  }
  String normalize(String name) {
    if (name.startsWith('simurghPatch_'))
      name = name.substring('simurghPatch_'.length);
    return names[name] ?? name;
  }

  String typeText(DartType type) {
    var result = type.toString();
    for (final e in names.entries) {
      result = result.replaceAll(e.key, e.value);
    }
    return result;
  }

  String? libraryName(Library lib) {
    final uri = lib.importUri.toString();
    if ((graph['libraries'] as Map).containsKey(uri)) return uri;
    final file = lib.fileUri.toString();
    if (!file.startsWith(root)) return null;
    final relative = file.substring(root.length);
    if (units.containsKey(relative)) return units[relative];
    if (relative == 'app.dart' || relative == 'module.dart') return 'app:entry';
    if (relative.startsWith('packages/')) {
      final parts = relative.split('/');
      return 'package:${parts[1]}/${parts.skip(3).join('/')}';
    }
    final logical = 'app:$relative';
    return (graph['libraries'] as Map).containsKey(logical) ? logical : null;
  }

  Object? describe(Constant value) {
    if (value is InstanceConstant) {
      final cls = value.classNode;
      final entity = entities[cls.name] as Map?;
      return {
        'class':
            '${entity?['library'] ?? libraryName(cls.enclosingLibrary) ?? cls.enclosingLibrary.importUri}::${normalize(cls.name)}',
        'types': value.typeArguments.map(typeText).toList(),
        'fields': {
          for (final e in value.fieldValues.entries)
            normalize(e.key.asField.name.text): describe(e.value),
        },
      };
    }
    if (value is StringConstant) return value.value;
    if (value is IntConstant) return value.value;
    if (value is DoubleConstant) return value.value;
    if (value is BoolConstant) return value.value;
    if (value is NullConstant) return null;
    if (value is ListConstant)
      return {
        'list': value.entries.map(describe).toList(),
        'type': typeText(value.typeArgument),
      };
    if (value is SetConstant)
      return {
        'set': value.entries.map(describe).toList(),
        'type': typeText(value.typeArgument),
      };
    if (value is MapConstant)
      return {
        'map': [
          for (final e in value.entries) [describe(e.key), describe(e.value)],
        ],
        'key_type': typeText(value.keyType),
        'value_type': typeText(value.valueType),
      };
    if (value is TypeLiteralConstant) return {'type': typeText(value.type)};
    if (value is StaticTearOffConstant)
      return {'tear_off': normalize(value.target.name.text)};
    throw StateError('Unhandled annotation constant: ${value.runtimeType}');
  }

  final declarations = <String, Object>{};
  final helpers = <String, Object>{};
  final classTypeParameters = <String, int>{};
  void collect(String path, Annotatable node, Map<String, Object> output) {
    if (node.annotations.isEmpty) return;
    output[path] = [
      for (final annotation in node.annotations)
        if (annotation is ConstantExpression)
          describe(annotation.constant)
        else
          throw StateError('Unevaluated annotation: $annotation'),
    ];
  }

  void function(
    String path,
    FunctionNode node,
    Map<String, Object> output, {
    String? bodyPath,
    Map<String, Object>? bodyOutput,
  }) {
    for (final e in node.typeParameters.indexed) {
      collect('$path/type:${e.$1}', e.$2, output);
    }
    for (final e in node.positionalParameters.indexed) {
      collect('$path/pos:${e.$1}', e.$2, output);
    }
    for (final e in node.namedParameters) {
      collect('$path/named:${normalize(e.name!)}', e, output);
    }
    node.body?.accept(
      _Locals(
        (local) {
          if (local.variable.name?.startsWith('simurgh') ?? false) return;
          final key = '${bodyPath ?? path}/local:${local.variable.name}';
          final localOutput = bodyOutput ?? output;
          collect(key, local.variable, localOutput);
          for (final e in local.function.positionalParameters.indexed) {
            collect('$key/pos:${e.$1}', e.$2, localOutput);
          }
          for (final e in local.function.typeParameters.indexed) {
            collect('$key/type:${e.$1}', e.$2, localOutput);
          }
        },
        (variable) {
          collect(
            '${bodyPath ?? path}/local-var:${variable.name}',
            variable,
            bodyOutput ?? output,
          );
        },
      ),
    );
  }

  for (final lib in component.libraries) {
    final owner = libraryName(lib);
    if (owner == null) continue;
    for (final cls in lib.classes) {
      final path = '$owner::class:${normalize(cls.name)}';
      classTypeParameters[path] = cls.typeParameters.length;
      collect(path, cls, declarations);
      for (final e in cls.typeParameters.indexed) {
        collect('$path/type:${e.$1}', e.$2, declarations);
      }
      for (final field in cls.fields) {
        collect(
          '$path/field:${normalize(field.name.text)}',
          field,
          declarations,
        );
      }
      for (final constructor in cls.constructors) {
        final key = '$path/constructor:${normalize(constructor.name.text)}';
        collect(key, constructor, declarations);
        function(key, constructor.function, declarations);
      }
      for (final method in cls.procedures) {
        final key = '$path/${method.kind.name}:${normalize(method.name.text)}';
        collect(key, method, declarations);
        function(key, method.function, declarations);
      }
    }
    for (final alias in lib.typedefs) {
      final path = '$owner::typedef:${normalize(alias.name)}';
      collect(path, alias, declarations);
      for (final e in alias.typeParameters.indexed) {
        collect('$path/type:${e.$1}', e.$2, declarations);
      }
    }
    for (final field in lib.fields) {
      collect(
        '$owner::global:${normalize(field.name.text)}',
        field,
        declarations,
      );
    }
    for (final method in lib.procedures) {
      final isHelper = method.name.text.contains('msbEntity_method_');
      final output = isHelper ? helpers : declarations;
      final path = '$owner::function:${normalize(method.name.text)}';
      // The module's loader is generated infrastructure, not the source main.
      if (method.name.text == 'main' &&
          lib.fileUri.path.endsWith('/module.dart'))
        continue;
      collect(path, method, output);
      String? bodyPath;
      if (isHelper) {
        final symbol = method.name.text.startsWith('simurghPatch_')
            ? method.name.text.substring('simurghPatch_'.length)
            : method.name.text;
        final entity = entities[symbol] as Map;
        final cls = entities[entity['owner']] as Map;
        final kind = (entity['kind'] as String).endsWith('getter')
            ? 'Getter'
            : (entity['kind'] as String).endsWith('setter')
            ? 'Setter'
            : (entity['kind'] as String).endsWith('operator')
            ? 'Operator'
            : 'Method';
        final member = (entity['name'] as String).substring(
          (cls['name'] as String).length + 1,
        );
        bodyPath = "$owner::class:${cls['name']}/$kind:$member";
      }
      function(
        path,
        method.function,
        output,
        bodyPath: bodyPath,
        bodyOutput: isHelper ? declarations : null,
      );
    }
  }
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'declarations': declarations,
      'helpers': helpers,
      'class_type_parameters': classTypeParameters,
    }),
  );
}

class _Locals extends RecursiveVisitor {
  _Locals(this.onLocal, this.onVariable);
  final void Function(FunctionDeclaration) onLocal;
  final void Function(VariableDeclaration) onVariable;
  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (node.parent is! FunctionNode &&
        node.parent is! FunctionDeclaration &&
        !(node.name?.startsWith('simurgh') ?? false))
      onVariable(node);
    super.visitVariableDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    onLocal(node);
    super.visitFunctionDeclaration(node);
  }
}
