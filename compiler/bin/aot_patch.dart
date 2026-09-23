// Experimental source-to-source front end for the first AOT/bytecode gate.
// Run with the package config of the Dart checkout pinned by toolchain.lock.json.
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:crypto/crypto.dart';

import '../lib/source_graph.dart';

Never reject(String message) => throw FormatException(message);
String hash(String value) => sha256.convert(utf8.encode(value)).toString();
const prefix = 'simurgh';
final toolchainHash = hash(
  File.fromUri(
    Platform.script.resolve('../../toolchain.lock.json'),
  ).readAsStringSync(),
);
final compilerHash = hash(
  [
    for (final path in [
      'bin/aot_patch.dart',
      'lib/source_graph.dart',
      'lib/class_lowering.dart',
      '../runtime/patches/manifest.json',
    ])
      '$path\u0000${hash(File.fromUri(Platform.script.resolve('../$path')).readAsStringSync())}\n',
  ].join(),
);
String baselineKey(String source) =>
    hash('m1-aot-v1\u0000$toolchainHash\u0000$compilerHash\u0000$source');
const primitiveTypes = {
  'int',
  'double',
  'num',
  'bool',
  'String',
  'void',
  'dynamic',
  'Object',
  'Null',
  'Never',
};

bool isTypeParameter(NamedType type) {
  AstNode? scope = type.parent;
  while (scope != null) {
    final TypeParameterList? parameters = switch (scope) {
      FunctionDeclaration() => scope.functionExpression.typeParameters,
      FunctionExpression() => scope.typeParameters,
      MethodDeclaration() => scope.typeParameters,
      GenericFunctionType() => scope.typeParameters,
      ClassDeclaration() => scope.namePart.typeParameters,
      ClassTypeAlias() => scope.typeParameters,
      MixinDeclaration() => scope.typeParameters,
      _ => null,
    };
    if (parameters?.typeParameters.any(
          (p) => p.name.lexeme == type.name.lexeme,
        ) ??
        false)
      return true;
    scope = scope.parent;
  }
  return false;
}

bool supportedTypeParameters(TypeParameterList? parameters) =>
    parameters == null ||
    parameters.typeParameters.every(
      (p) => p.metadata.isEmpty && (p.bound == null || supportedType(p.bound)),
    );

bool supportedType(TypeAnnotation? type, {bool allowVoid = true}) {
  if (type is NamedType) {
    if (type.typeArguments == null &&
        type.importPrefix == null &&
        isTypeParameter(type))
      return true;
    if (linkedSdkLibraries.any(
      (uri) => type.importPrefix?.name.lexeme == sdkPrefix(uri),
    )) {
      return type.typeArguments?.arguments.every(
            (argument) => supportedType(argument, allowVoid: false),
          ) ??
          true;
    }
    if (type.name.lexeme == 'Future' && type.importPrefix == null) {
      final arguments = type.typeArguments?.arguments;
      return arguments != null &&
          arguments.length == 1 &&
          supportedType(arguments.single);
    }
    return (primitiveTypes.contains(type.name.lexeme) &&
            (allowVoid || type.toSource() != 'void')) ||
        (type.name.lexeme.startsWith('${entityPrefix}class_') &&
            (type.typeArguments?.arguments.every(
                  (argument) => supportedType(argument, allowVoid: false),
                ) ??
                true) &&
            type.importPrefix == null);
  }
  if (type is GenericFunctionType) {
    return supportedTypeParameters(type.typeParameters) &&
        supportedType(type.returnType) &&
        type.parameters.parameters.every(supportedParameter);
  }
  return false;
}

bool isFutureType(TypeAnnotation? type) =>
    type is NamedType &&
    type.name.lexeme == 'Future' &&
    type.typeArguments?.arguments.length == 1;

bool supportedParameter(FormalParameter param) {
  final base = unwrapParameter(param);
  return base is SimpleFormalParameter &&
      base.metadata.isEmpty &&
      base.covariantKeyword == null &&
      supportedType(base.type, allowVoid: false);
}

void validateParameters(FormalParameterList parameters) {
  for (final param in parameters.parameters) {
    if (!supportedParameter(param) || param.name == null) {
      reject('Only explicitly typed supported parameters allowed');
    }
  }
}

class Program {
  Program(this.source, this.identity) {
    final parsed = parseString(content: source, throwIfDiagnostics: false);
    if (parsed.errors.isNotEmpty)
      reject('Invalid Dart source: ${parsed.errors}');
    final unit = parsed.unit;
    if (unit.directives.map((d) => d.toSource()).join('\n') != sdkImports) {
      reject('Expected canonical linked SDK imports');
    }
    for (final declaration in unit.declarations) {
      if (declaration is ClassDeclaration ||
          declaration is ClassTypeAlias ||
          declaration is MixinDeclaration) {
        if (!supportedTypeParameters(declaration.typeParameters))
          reject('Unsupported class type parameter bounds');
        classes[declaration.typeName.lexeme] = declaration;
        continue;
      }
      if (declaration is TopLevelVariableDeclaration) {
        if (declaration.metadata.isNotEmpty ||
            declaration.externalKeyword != null ||
            !supportedType(declaration.variables.type)) {
          reject(
            'Globals require an explicit supported type without annotations',
          );
        }
        for (final variable in declaration.variables.variables) {
          globals[variable.name.lexeme] = declaration;
        }
        continue;
      }
      if (declaration is! FunctionDeclaration) {
        reject(
          'M1 subset accepts synchronous top-level functions only; '
          'classes, fields and extensions require layout/dependency support',
        );
      }
      final name = declaration.name.lexeme;
      if (name.startsWith('_') || name.startsWith(prefix)) {
        reject('Private or reserved function name: $name');
      }
      if (functions.containsKey(name)) reject('Duplicate function: $name');
      final fn = declaration.functionExpression;
      if (declaration.isGetter ||
          declaration.isSetter ||
          declaration.externalKeyword != null ||
          declaration.metadata.isNotEmpty ||
          !supportedTypeParameters(fn.typeParameters) ||
          fn.body.isGenerator ||
          fn.body is EmptyFunctionBody) {
        reject(
          'Unsupported function kind, annotation or generic signature: $name',
        );
      }
      if (!supportedType(declaration.returnType)) {
        reject('Explicit primitive or function return type required: $name');
      }
      if (fn.body.isAsynchronous &&
          !isFutureType(declaration.returnType) &&
          declaration.returnType!.toSource() != 'dynamic') {
        reject('Async declarations require a Future or dynamic return type');
      }
      validateParameters(fn.parameters!);
      functions[name] = declaration;
    }
    if (!functions.containsKey('main') ||
        functions['main']!.functionExpression.typeParameters != null ||
        !{
          'void',
          'dynamic',
          'Future<void>',
        }.contains(functions['main']!.returnType!.toSource()) ||
        functions['main']!
            .functionExpression
            .parameters!
            .parameters
            .isNotEmpty) {
      reject(
        'A void, dynamic or Future<void> main() entry point is required for this gate',
      );
    }
    for (final declaration in functions.values) {
      for (final param
          in declaration.functionExpression.parameters!.parameters) {
        if (functions.containsKey(param.name!.lexeme) ||
            param.name!.lexeme.startsWith(prefix)) {
          reject('Parameter shadows a program or generated entity');
        }
      }
      declaration.functionExpression.body.accept(
        BodyGuard(functions.keys.toSet()),
      );
    }
  }
  final String source;
  final String identity;
  String get languageVersion =>
      (jsonDecode(identity) as Map<String, dynamic>)['language_version']
          as String;
  Map<String, String> get libraryVersions =>
      ((jsonDecode(identity)
                  as Map<String, dynamic>)['library_language_versions']
              as Map)
          .cast<String, String>();
  bool get splitLibraries => libraryVersions.values.toSet().length > 1;
  String libraryFile(String uri) => 'unit_${hash(uri)}.dart';
  String entityFile(String name) => splitLibraries
      ? libraryFile((entities[name] as Map)['library'] as String)
      : 'app.dart';
  List<Map<String, dynamic>> get dynamicRoots =>
      ((jsonDecode(identity) as Map<String, dynamic>)['dynamic_retention_roots']
              as List)
          .cast<Map<String, dynamic>>();
  List<String> get dynamicSelectors =>
      dynamicRoots.map((root) => root['selector'] as String).toSet().toList()
        ..sort();

  Map<String, dynamic> get entities =>
      (jsonDecode(identity) as Map<String, dynamic>)['entities']
          as Map<String, dynamic>;
  String entityId(String name) =>
      (entities[name] as Map<String, dynamic>)['entity'] as String;
  final functions = <String, FunctionDeclaration>{};
  final classes = <String, CompilationUnitMember>{};
  final globals = <String, TopLevelVariableDeclaration>{};
  String signature(FunctionDeclaration f) =>
      '${f.returnType!.toSource()} ${f.name.lexeme}${f.functionExpression.typeParameters?.toSource() ?? ''}${f.functionExpression.parameters!.toSource()}';
  Map<String, Object?> manifest() => {
    'schema': 1,
    'language_version': languageVersion,
    'library_language_versions': libraryVersions,
    'emitted_libraries': {
      for (final uri in libraryVersions.keys)
        uri: splitLibraries ? libraryFile(uri) : 'app.dart',
    },
    'subset': 'm1-sync-top-level-functions-and-closures',
    'source_sha256': hash(source),
    'source_graph_sha256': hash(identity),
    'entities': entities,
    'toolchain_sha256': toolchainHash,
    'compiler_sha256': compilerHash,
    'baseline_fingerprint': baselineKey(identity),
    'global_declarations': {
      for (final entry in globals.entries)
        entry.key: hash(entry.value.toSource()),
    },
    'dynamic_interface_sha256': hash(dynamicInterfaceText(this)),
    'dynamic_selectors': dynamicSelectors,
    'dynamic_retention_root_count': dynamicRoots.length,
    'class_shapes': {
      for (final entry in classes.entries)
        entry.key: hash(entry.value.toSource()),
    },
    'functions': {
      for (final entry in functions.entries)
        entry.key: {
          'entity': entityId(entry.key),
          'signature': signature(entry.value),
          'body_sha256': hash(entry.value.functionExpression.body.toSource()),
          'calls': (CallEdits(
            functions.keys.toSet(),
          )..walk(entry.value.functionExpression.body)).calls.toList()..sort(),
        },
    },
  };
}

// This single-library subset prohibits shadowing of program/generated names.
// Only unqualified calls and expression references may name program functions;
// member names, labels and type names must not be rewritten as function values.
bool isFunctionReference(SimpleIdentifier node) {
  final parent = node.parent;
  if (parent is MethodInvocation) {
    return parent.target == null && parent.methodName == node;
  }
  return (parent is VariableDeclaration && parent.initializer == node) ||
      (parent is ArgumentList && parent.arguments.contains(node)) ||
      (parent is ReturnStatement && parent.expression == node) ||
      (parent is AssignmentExpression && parent.rightHandSide == node) ||
      (parent is ParenthesizedExpression && parent.expression == node) ||
      (parent is BinaryExpression &&
          (parent.leftOperand == node || parent.rightOperand == node)) ||
      (parent is ConditionalExpression &&
          (parent.thenExpression == node || parent.elseExpression == node)) ||
      (parent is ExpressionFunctionBody && parent.expression == node) ||
      (parent is NamedExpression && parent.expression == node) ||
      (parent is DefaultFormalParameter && parent.defaultValue == node) ||
      (parent is FunctionReference && parent.function == node) ||
      (parent is ListLiteral && parent.elements.contains(node));
}

class BodyGuard extends RecursiveAstVisitor<void> {
  BodyGuard(this.names);
  final Set<String> names;
  @override
  void visitFunctionExpression(FunctionExpression node) {
    if (!supportedTypeParameters(node.typeParameters) ||
        node.body.isGenerator ||
        node.body is EmptyFunctionBody) {
      reject('Unsupported generic bounds or generator closure');
    }
    validateParameters(node.parameters!);
    for (final param in node.parameters!.parameters) {
      if (names.contains(param.name!.lexeme) ||
          param.name!.lexeme.startsWith(prefix)) {
        reject('Closure parameter shadows a program or generated entity');
      }
    }
    super.visitFunctionExpression(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (names.contains(node.name.lexeme) ||
        node.name.lexeme.startsWith(prefix)) {
      reject('Local function shadows a program or generated entity');
    }
    if (node.metadata.isNotEmpty || !supportedType(node.returnType)) {
      reject('Local functions require a supported explicit return type');
    }
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitCatchClauseParameter(CatchClauseParameter node) {
    if (names.contains(node.name.lexeme) ||
        node.name.lexeme.startsWith(prefix)) {
      reject('Catch parameter shadows a program or generated entity');
    }
    super.visitCatchClauseParameter(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.name.startsWith(prefix))
      reject('Reserved identifier: ${node.name}');
    if (names.contains(node.name)) {
      if (!isFunctionReference(node)) {
        reject('Unsupported function reference or shadowing: ${node.name}');
      }
    }
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (names.contains(node.name.lexeme) ||
        node.name.lexeme.startsWith(prefix)) {
      reject('Local variable shadows a program or generated entity');
    }
    super.visitVariableDeclaration(node);
  }
}

class CallEdits extends RecursiveAstVisitor<void> {
  CallEdits(
    this.names, [
    this.classNames = const {},
    this.globalNames = const {},
  ]);
  final Set<String> names;
  final Set<String> classNames;
  final Set<String> globalNames;
  final calls = <String>{};
  final offsets = <int, String>{};
  final interpolations = <int>{};
  void walk(AstNode node) => node.accept(this);
  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if ((names.contains(node.name) && isFunctionReference(node)) ||
        classNames.contains(node.name) ||
        globalNames.contains(node.name)) {
      calls.add(node.name);
      offsets[node.offset] = node.name;
      if (node.parent is InterpolationExpression &&
          (node.parent as InterpolationExpression).rightBracket == null) {
        interpolations.add(node.offset);
      }
    }
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitNamedType(NamedType node) {
    if (classNames.contains(node.name.lexeme))
      offsets[node.name.offset] = node.name.lexeme;
    super.visitNamedType(node);
  }
}

String nodeText(
  Program program,
  AstNode node, {
  Set<String>? baselineNames,
  Set<String>? baselineClasses,
  Set<String>? baselineGlobals,
}) {
  var text = program.source.substring(node.offset, node.end);
  if (baselineNames != null) {
    final edits = CallEdits(
      program.functions.keys.toSet(),
      program.classes.keys.toSet(),
      program.globals.keys.toSet(),
    )..walk(node);
    for (final offset
        in edits.offsets.keys.toList()..sort((a, b) => b.compareTo(a))) {
      final relative = offset - node.offset;
      final name = edits.offsets[offset]!;
      final isClass = program.classes.containsKey(name);
      final qualifier = program.globals.containsKey(name)
          ? ((baselineGlobals ?? program.globals.keys.toSet()).contains(name)
                ? '${prefix}Baseline.'
                : '')
          : isClass
          ? ((baselineClasses ?? program.classes.keys.toSet()).contains(name)
                ? '${prefix}Baseline.'
                : '')
          : (baselineNames.contains(name)
                ? '${prefix}Baseline.'
                : '${prefix}Patch_');
      if (edits.interpolations.contains(offset)) {
        text =
            '${text.substring(0, relative)}{$qualifier$name}${text.substring(relative + name.length)}';
      } else {
        text =
            '${text.substring(0, relative)}$qualifier${text.substring(relative)}';
      }
    }
  }
  return text;
}

String bodyText(
  Program program,
  FunctionDeclaration f, {
  Set<String>? baselineNames,
  Set<String>? baselineClasses,
  Set<String>? baselineGlobals,
}) {
  final body = f.functionExpression.body;
  final text = nodeText(
    program,
    body,
    baselineNames: baselineNames,
    baselineClasses: baselineClasses,
    baselineGlobals: baselineGlobals,
  );
  if (body is ExpressionFunctionBody) {
    final expression = nodeText(
      program,
      body.expression,
      baselineNames: baselineNames,
      baselineClasses: baselineClasses,
      baselineGlobals: baselineGlobals,
    );
    final action = f.returnType!.toSource() == 'void'
        ? '$expression;'
        : 'return $expression;';
    return '${body.isAsynchronous ? 'async ' : ''}{ $action }';
  }
  return text;
}

// The merged AST is an analysis representation only. Mixed language graphs
// are emitted as separate CFE libraries, preserving their language semantics.
void writeLinkedSources(
  Program program,
  String text,
  Directory output,
  String primary, {
  required bool isPatch,
}) {
  if (!program.splitLibraries) {
    File('${output.path}/$primary').writeAsStringSync(
      text.replaceFirst('\n', '\nlibrary simurgh_generated_v1;\n'),
    );
    return;
  }
  final unit = parseString(content: text, throwIfDiagnostics: true).unit;
  final imports = unit.directives.map((d) => d.toSource()).join('\n');
  final bodies = {
    for (final uri in program.libraryVersions.keys) uri: StringBuffer(),
  };
  final infrastructure = StringBuffer();
  for (final declaration in unit.declarations) {
    String? name;
    if (declaration is FunctionDeclaration) {
      name = declaration.name.lexeme;
      if (isPatch) {
        name = name.startsWith('${prefix}Patch_')
            ? name.substring('${prefix}Patch_'.length)
            : null;
      }
    } else if (declaration is ClassDeclaration ||
        declaration is ClassTypeAlias ||
        declaration is MixinDeclaration) {
      name = declaration.typeName.lexeme;
    } else if (declaration is TopLevelVariableDeclaration) {
      name = declaration.variables.variables.first.name.lexeme;
    }
    final entity = program.entities[name];
    final buffer = entity == null
        ? infrastructure
        : bodies[(entity as Map)['library']]!;
    buffer.writeln(declaration.toSource());
  }
  final facade = StringBuffer(
    '// @dart=${program.languageVersion}\n$imports\n',
  );
  for (final entry in bodies.entries) {
    final file = program.libraryFile(entry.key);
    facade.writeln("import '$file';\nexport '$file';");
    File('${output.path}/$file').writeAsStringSync(
      '// @dart=${program.libraryVersions[entry.key]}\nlibrary simurgh_generated_v1;\n$imports\n'
      "import '$primary';\n${entry.value}",
    );
  }
  facade.write(infrastructure);
  File('${output.path}/$primary').writeAsStringSync(facade.toString());
}

void baseline(Program program, Directory output) {
  final generated = StringBuffer(
    '// @dart=${program.languageVersion}\n// Generated M1 experimental AOT baseline.\n$sdkImports\n',
  );
  for (final declaration in program.globals.values.toSet()) {
    generated.writeln(declaration.toSource());
  }
  for (final declaration in program.classes.values) {
    generated.writeln(declaration.toSource());
  }
  var index = 0;
  final names = program.functions.keys.toList()..sort();
  for (final name in names) {
    final f = program.functions[name]!;
    final parameters = f.functionExpression.parameters!.parameters;
    final type =
        '${f.returnType!.toSource()} Function${f.functionExpression.typeParameters?.toSource() ?? ''}('
        '${dispatchParameterTypes(parameters)})';
    generated.writeln('$type? ${prefix}Slot$index;');
    index++;
  }
  generated.writeln(
    'void ${prefix}Install(String fingerprint, Map<String, Function> updates) {',
  );
  generated.writeln(
    "if (fingerprint != '${baselineKey(program.identity)}') { throw StateError('Wrong baseline fingerprint'); }",
  );
  generated.writeln(
    'if (updates.keys.any((key) => !${jsonEncode(names)}.contains(key))) '
    "{ throw StateError('Unknown patch entity'); }",
  );
  index = 0;
  for (final name in names) {
    final f = program.functions[name]!;
    final type =
        '${f.returnType!.toSource()} Function${f.functionExpression.typeParameters?.toSource() ?? ''}('
        '${dispatchParameterTypes(f.functionExpression.parameters!.parameters)})';
    generated.writeln(
      "if (updates.containsKey('$name') && updates['$name'] is! $type) "
      "{ throw StateError('Patch signature mismatch: $name'); }",
    );
    index++;
  }
  index = 0;
  for (final name in names) {
    final f = program.functions[name]!;
    final type =
        '${f.returnType!.toSource()} Function${f.functionExpression.typeParameters?.toSource() ?? ''}('
        '${dispatchParameterTypes(f.functionExpression.parameters!.parameters)})';
    generated.writeln(
      "if (updates.containsKey('$name')) ${prefix}Slot$index = updates['$name'] as $type;",
    );
    index++;
  }
  generated.writeln('}');
  index = 0;
  for (final name in names) {
    final f = program.functions[name]!;
    final args = forwardArguments(f.functionExpression.parameters!.parameters);
    final types = forwardTypeArguments(f.functionExpression.typeParameters);
    final body = bodyText(program, f);
    generated.writeln('${program.signature(f)} {');
    generated.writeln('final ${prefix}Replacement = ${prefix}Slot$index;');
    generated.writeln('if (${prefix}Replacement != null) {');
    if (f.returnType!.toSource() == 'void') {
      generated.writeln('${prefix}Replacement$types($args); return;');
    } else {
      generated.writeln('return ${prefix}Replacement$types($args);');
    }
    generated.writeln('}');
    if (f.functionExpression.body.isAsynchronous) {
      // Keep dispatch synchronous: adding another async wrapper would change
      // Future identity and introduce an extra completion boundary.
      // An inferred closure could narrow Future<num> to Future<int>. Keep
      // the original declared return type on the local async function.
      generated.writeln(
        '${f.returnType!.toSource()} ${prefix}OriginalBody() $body',
      );
      generated.writeln('return ${prefix}OriginalBody();');
    } else {
      generated.writeln(body.substring(1, body.length - 1));
    }
    generated.writeln('}');
    index++;
  }
  var retentionIndex = 0;
  for (final root in program.dynamicRoots) {
    generated.writeln(
      'dynamic ${prefix}Retain${retentionIndex++}(${root['parameters']}) => ${root['expression']};',
    );
  }
  writeLinkedSources(
    program,
    generated.toString(),
    output,
    'app.dart',
    isPatch: false,
  );
  File('${output.path}/source.dart').writeAsStringSync(program.source);
  File('${output.path}/source_graph.json').writeAsStringSync(program.identity);
  File('${output.path}/manifest.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(program.manifest())}\n',
  );
  File(
    '${output.path}/dynamic_interface.yaml',
  ).writeAsStringSync(dynamicInterfaceText(program));
  File('${output.path}/launcher.dart').writeAsStringSync("""
import 'dart:io';
import 'package:dynamic_modules/dynamic_modules.dart';
import 'app.dart' as app;
Future<void> main(List<String> args) async {
  if (args.length > 1) throw ArgumentError('Expected zero or one local bytecode path');
  if (args.isNotEmpty) await loadModuleFromBytes(File(args.single).readAsBytesSync());
  ${program.functions['main']!.returnType!.toSource() == 'void' ? 'app.main();' : 'await app.main();'}
}
""");
}

String dynamicInterfaceText(Program program) =>
    "callable:\n${linkedSdkLibraries.map((uri) => "  - library: '$uri'\n").join()}  - library: 'app.dart'\n${program.splitLibraries ? program.libraryVersions.keys.map((uri) => "  - library: '${program.libraryFile(uri)}'\n").join() : ''}"
    '${dynamicClassInterface(program)}'
    'dynamic-callable-selectors:\n${program.dynamicSelectors.map((selector) => '  - ${jsonEncode(selector)}\n').join()}';

String dynamicClassInterface(Program program) {
  final openClasses =
      program.classes.entries
          .where(
            (entry) =>
                entry.value.finalKeyword == null &&
                entry.value.sealedKeyword == null,
          )
          .map((entry) => entry.key)
          .toList()
        ..sort();
  final graph = jsonDecode(program.identity) as Map;
  final sdkClasses = <String, Map>{
    for (final entry in [
      ...graph['sdk_interfaces'],
      ...graph['sdk_superclasses'],
      ...graph['sdk_mixins'],
    ])
      "${entry['library']}::${entry['class']}": entry as Map,
  }.values.toList();
  if (openClasses.isEmpty && sdkClasses.isEmpty) return '';
  final sdkContracts = sdkClasses
      .map(
        (entry) =>
            "  - library: '${entry['library']}'\n    class: '${entry['class']}'\n",
      )
      .join();
  return [
    for (final capability in ['extendable', 'can-be-overridden'])
      '$capability:\n$sdkContracts${openClasses.map((name) => "  - library: '${program.entityFile(name)}'\n    class: '$name'\n").join()}',
  ].join();
}

class EntityReferences extends RecursiveAstVisitor<void> {
  EntityReferences(this.names);
  final Set<String> names;
  final references = <String>{};
  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (names.contains(node.name)) references.add(node.name);
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitNamedType(NamedType node) {
    if (names.contains(node.name.lexeme)) references.add(node.name.lexeme);
    super.visitNamedType(node);
  }
}

Set<String> referencesTo(AstNode node, Set<String> names) {
  final visitor = EntityReferences(names);
  node.accept(visitor);
  return visitor.references;
}

Set<String> signatureReferences(
  FunctionDeclaration function,
  Set<String> names,
) {
  final visitor = EntityReferences(names);
  function.returnType?.accept(visitor);
  function.functionExpression.typeParameters?.accept(visitor);
  function.functionExpression.parameters?.accept(visitor);
  return visitor.references;
}

Future<void> patch(Program program, Directory base, Directory output) async {
  final original = Program(
    File('${base.path}/source.dart').readAsStringSync(),
    File('${base.path}/source_graph.json').readAsStringSync(),
  );
  final manifest = jsonDecode(
    File('${base.path}/manifest.json').readAsStringSync(),
  );
  for (final entry in original.libraryVersions.entries) {
    if (program.libraryVersions.containsKey(entry.key) &&
        program.libraryVersions[entry.key] != entry.value) {
      reject('Language version changes require a new baseline: ${entry.key}');
    }
  }
  if (manifest['dynamic_interface_sha256'] !=
          hash(dynamicInterfaceText(original)) ||
      manifest['dynamic_interface_sha256'] !=
          hash(
            File('${base.path}/dynamic_interface.yaml').readAsStringSync(),
          ) ||
      manifest['source_sha256'] != hash(original.source) ||
      manifest['source_graph_sha256'] != hash(original.identity) ||
      manifest['baseline_fingerprint'] != baselineKey(original.identity) ||
      manifest['compiler_sha256'] != compilerHash ||
      manifest['toolchain_sha256'] != toolchainHash) {
    reject('Baseline source, compiler or toolchain fingerprint mismatch');
  }
  final before = original.functions.keys.toSet();
  final originalClasses = original.classes.keys.toSet();
  // Immutable compiler-generated adapters can become unused when an index
  // setter or a private interface obligation is removed. They remain in the baseline snapshot; no user
  // class deletion or live-object migration is permitted by this exception.
  final retiredInfrastructure = originalClasses
      .difference(program.classes.keys.toSet())
      .where(
        (name) => const {
          'super-index-cell',
          'private-interface-trap',
          'alias-interface-mixin',
        }.contains(original.entities[name]?['generated']),
      )
      .toSet();
  for (final declaration in <AstNode>[
    ...program.classes.values,
    ...program.functions.values,
    ...program.globals.values,
  ]) {
    if (referencesTo(declaration, retiredInfrastructure).isNotEmpty) {
      reject('Retired infrastructure is still referenced');
    }
  }
  originalClasses.removeAll(retiredInfrastructure);
  if (!program.classes.keys.toSet().containsAll(originalClasses)) {
    reject('Deleted classes require reference removal proof (not implemented)');
  }
  final originalGlobals = original.globals.keys.toSet();
  if (!program.globals.keys.toSet().containsAll(originalGlobals)) {
    reject('Deleted globals require reference removal proof (not implemented)');
  }
  final replacedGlobals = <String>{
    for (final name in originalGlobals)
      if (original.globals[name]!.toSource() !=
          program.globals[name]!.toSource())
        name,
  };
  final changedGlobals = replacedGlobals.toList()..sort();
  final replacedClasses = <String>{
    for (final name in originalClasses)
      if (original.classes[name]!.toSource() !=
          program.classes[name]!.toSource())
        name,
  };
  final structuralChanges = replacedClasses.toList()..sort();
  final moduleOnly = <String>{};
  final invalidated = <String>{};
  // A changed class gets a fresh module-local identity. Rebind every typed
  // dependency; never install a new-layout function into an old-layout slot.
  // This is limited to the resolved, closed source graph accepted by this lab.
  var grew = true;
  while (grew) {
    final size =
        replacedClasses.length +
        replacedGlobals.length +
        moduleOnly.length +
        invalidated.length;
    for (final name in program.functions.keys) {
      final current = program.functions[name]!;
      final signature = signatureReferences(current, {
        ...replacedClasses,
        ...replacedGlobals,
        ...moduleOnly,
      });
      if (before.contains(name)) {
        signature.addAll(
          signatureReferences(original.functions[name]!, {
            ...replacedClasses,
            ...replacedGlobals,
            ...moduleOnly,
          }),
        );
      }
      if (signature.isNotEmpty ||
          (before.contains(name) &&
              replacedClasses.contains(program.entities[name]?['owner']))) {
        // Static helpers have no receiver type in their signature. A replaced
        // declaring class still owns their new signature/storage semantics;
        // keep those helpers module-local, just like instance helpers.
        moduleOnly.add(name);
      }
      if (referencesTo(current, {
        ...replacedClasses,
        ...replacedGlobals,
        ...moduleOnly,
      }).isNotEmpty)
        invalidated.add(name);
    }
    for (final name in originalGlobals) {
      final declaration = program.globals[name]!;
      if (referencesTo(declaration, {
            ...replacedClasses,
            ...replacedGlobals,
            ...moduleOnly,
          }).isNotEmpty ||
          declaration.variables.variables.any(
            (v) => replacedGlobals.contains(v.name.lexeme),
          )) {
        replacedGlobals.addAll(
          declaration.variables.variables.map((v) => v.name.lexeme),
        );
      }
    }
    for (final name in originalClasses) {
      if (referencesTo(program.classes[name]!, {
        ...replacedClasses,
        ...replacedGlobals,
        ...moduleOnly,
      }).isNotEmpty) {
        replacedClasses.add(name);
      }
    }
    // Implementations of a closed baseline type cannot cross a generated
    // library/module boundary. Recreate that family when the original source
    // permits a new/local implementation; source analysis already enforces
    // Dart's library-level modifier restrictions.
    for (final entry in program.classes.entries) {
      if (originalClasses.contains(entry.key) &&
          !replacedClasses.contains(entry.key))
        continue;
      for (final type
          in entry.value.implementsClause?.interfaces ?? <NamedType>[]) {
        final parent = type.name.lexeme;
        final parentClass = original.classes[parent];
        if (parentClass != null &&
            (parentClass.finalKeyword != null ||
                parentClass.sealedKeyword != null ||
                parentClass.baseKeyword != null)) {
          replacedClasses.add(parent);
        }
      }
    }
    for (final name in replacedClasses.toList()) {
      final parent =
          program.classes[name]!.extendsClause?.superclass.name.lexeme;
      final parentClass = original.classes[parent];
      if (parentClass != null &&
          (parentClass.finalKeyword != null ||
              parentClass.sealedKeyword != null ||
              parentClass.interfaceKeyword != null)) {
        replacedClasses.add(parent!);
      }
    }
    grew =
        size !=
        replacedClasses.length +
            replacedGlobals.length +
            moduleOnly.length +
            invalidated.length;
  }
  final baselineClasses = originalClasses.difference(replacedClasses);
  final baselineGlobals = originalGlobals.difference(replacedGlobals);
  final addedGlobals = program.globals.keys.toSet().difference(originalGlobals);
  final moduleGlobals = {...replacedGlobals, ...addedGlobals};
  final baselineFunctions = before.difference(moduleOnly);
  final addedClasses =
      program.classes.keys.toSet().difference(originalClasses).toList()..sort();
  final moduleClasses = {...addedClasses, ...replacedClasses}.toList()..sort();
  for (final name in moduleClasses) {
    final parent = program.classes[name]!.extendsClause?.superclass.name.lexeme;
    final baseClass = baselineClasses.contains(parent)
        ? original.classes[parent]
        : null;
    if (baseClass != null &&
        (baseClass.finalKeyword != null ||
            baseClass.sealedKeyword != null ||
            baseClass.interfaceKeyword != null)) {
      reject(
        'New class cannot extend a closed baseline class across a module boundary: $parent',
      );
    }
  }
  final removed = before.difference(program.functions.keys.toSet());
  for (final name in removed) {
    if (!replacedClasses.contains(original.entities[name]?['owner'])) {
      reject(
        'Deleted functions require reference removal proof (not implemented)',
      );
    }
  }
  baselineFunctions.removeAll(removed);
  final changed = <String>[];
  final added = program.functions.keys.toSet().difference(before).toList()
    ..sort();
  final rebound = <String, List<String>>{};
  for (final name in before.difference(removed)) {
    final old = original.functions[name]!;
    final current = program.functions[name]!;
    if (original.signature(old) != program.signature(current) &&
        !moduleOnly.contains(name))
      reject('Signature changed: $name');
    // A new declaration may shadow a dart:core function used by an otherwise
    // textually unchanged caller. That caller must leave AOT as well.
    final newReferences = CallEdits(added.toSet())
      ..walk(current.functionExpression.body);
    if (newReferences.calls.isNotEmpty) {
      rebound[name] = newReferences.calls.toList()..sort();
    }
    if (old.functionExpression.body.toSource() !=
            current.functionExpression.body.toSource() ||
        rebound.containsKey(name) ||
        invalidated.contains(name) ||
        moduleOnly.contains(name))
      changed.add(name);
  }
  changed.sort();
  if (changed.isEmpty &&
      added.isEmpty &&
      moduleClasses.isEmpty &&
      moduleGlobals.isEmpty)
    reject('No function body changes');
  final source = StringBuffer(
    '// @dart=${program.languageVersion}\n$sdkImports\nimport ${jsonEncode(File('${base.path}/app.dart').absolute.uri.toString())} as ${prefix}Baseline;\n',
  );
  for (final declaration
      in moduleGlobals.map((name) => program.globals[name]!).toSet()) {
    source.writeln(
      nodeText(
        program,
        declaration,
        baselineNames: baselineFunctions,
        baselineClasses: baselineClasses,
        baselineGlobals: baselineGlobals,
      ),
    );
  }
  for (final name in moduleClasses) {
    source.writeln(
      nodeText(
        program,
        program.classes[name]!,
        baselineNames: baselineFunctions,
        baselineClasses: baselineClasses,
        baselineGlobals: baselineGlobals,
      ),
    );
  }
  for (final name in [...changed, ...added]) {
    final f = program.functions[name]!;
    source.writeln(
      '${nodeText(program, f.returnType!, baselineNames: baselineFunctions, baselineClasses: baselineClasses, baselineGlobals: baselineGlobals)} ${prefix}Patch_$name'
      '${f.functionExpression.typeParameters == null ? '' : nodeText(program, f.functionExpression.typeParameters!, baselineNames: baselineFunctions, baselineClasses: baselineClasses, baselineGlobals: baselineGlobals)}'
      '${nodeText(program, f.functionExpression.parameters!, baselineNames: baselineFunctions, baselineClasses: baselineClasses, baselineGlobals: baselineGlobals)} ${bodyText(program, f, baselineNames: baselineFunctions, baselineClasses: baselineClasses, baselineGlobals: baselineGlobals)}',
    );
  }
  source.writeln("@pragma('dyn-module:entry-point')\nvoid main() {");
  source.writeln(
    "${prefix}Baseline.${prefix}Install('${baselineKey(original.identity)}', {",
  );
  for (final name in changed.where((name) => !moduleOnly.contains(name))) {
    source.writeln('${jsonEncode(name)}: ${prefix}Patch_$name,');
  }
  source.writeln('});\n}');
  output.createSync(recursive: true);
  writeLinkedSources(
    program,
    source.toString(),
    output,
    'module.dart',
    isPatch: true,
  );
  File('${output.path}/source_graph.json').writeAsStringSync(program.identity);
  File('${output.path}/manifest.json').writeAsStringSync(
    jsonEncode({
      'schema': 1,
      'experimental': true,
      'baseline_source_sha256': hash(original.source),
      'candidate_source_sha256': hash(program.source),
      'candidate_source_graph_sha256': hash(program.identity),
      'entities': program.entities,
      'changed_functions': changed,
      'added_functions': added,
      'added_classes': addedClasses,
      'changed_globals': changedGlobals,
      'replaced_globals': replacedGlobals.toList()..sort(),
      'added_globals': addedGlobals.toList()..sort(),
      'structurally_changed_classes': structuralChanges,
      'replaced_classes': replacedClasses.toList()..sort(),
      'invalidated_functions': invalidated.toList()..sort(),
      'module_only_functions': moduleOnly.toList()..sort(),
      'installed_functions': changed
          .where((name) => !moduleOnly.contains(name))
          .toList(),
      'retired_functions': removed.toList()..sort(),
      'retired_infrastructure_classes': retiredInfrastructure.toList()..sort(),
      'rebound_callers': rebound,
      'module_entities': {
        for (final name in [...changed, ...added])
          name: {
            'entity': program.entityId(name),
            'signature': program.signature(program.functions[name]!),
            'references': {
              for (final target in (CallEdits(
                program.functions.keys.toSet(),
              )..walk(program.functions[name]!.functionExpression.body)).calls)
                target: baselineFunctions.contains(target)
                    ? 'baseline-entry'
                    : 'module-function',
            },
          },
      },
      'baseline_fingerprint': baselineKey(original.identity),
      'toolchain_sha256': toolchainHash,
      'compiler_sha256': compilerHash,
      'complete_runtime_implemented': false,
      'production_patch': false,
    }),
  );
}

Future<void> main(List<String> args) async {
  try {
    if (args.length < 3 ||
        !{'baseline', 'patch'}.contains(args[0]) ||
        (args[0] == 'baseline' ? args.length != 3 : args.length != 4)) {
      reject(
        'Usage: aot_patch.dart baseline SOURCE NEW_OUTPUT | patch SOURCE BASELINE NEW_OUTPUT',
      );
    }
    final file = File(args[1]);
    final output = Directory(args.last);
    if (output.existsSync())
      reject('Output already exists; refusing to overwrite');
    final graph = await loadSourceGraph(file);
    final program = Program(graph.source, graph.identity);
    if (args[0] == 'baseline') {
      output.createSync(recursive: true);
      baseline(program, output);
    } else {
      await patch(program, Directory(args[2]), output);
    }
    stdout.writeln(
      jsonEncode({'output': output.absolute.path, 'experimental': true}),
    );
  } on Object catch (error) {
    stderr.writeln(error);
    exitCode = 2;
  }
}
