// Resolves a local Dart library graph before lowering its top-level functions.
// Library identity and privacy are checked on the original, unmodified sources.
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer/src/dart/analysis/analysis_context_collection.dart';
import 'package:crypto/crypto.dart';
import 'package:package_config/package_config.dart';
import 'package:yaml/yaml.dart';

part 'class_lowering.dart';

bool supportsAsyncReturn(DartType type) =>
    type is DynamicType ||
    (type is InterfaceType &&
        type.element.name == 'Future' &&
        type.element.library.uri.toString() == 'dart:async');

// Shared class, enum, mixin and named application view, preserving resolved nodes.
extension ProgramTypeDeclaration on CompilationUnitMember {
  Token get typeName => switch (this) {
    ClassDeclaration c => c.namePart.typeName,
    EnumDeclaration e => e.namePart.typeName,
    ClassTypeAlias c => c.name,
    MixinDeclaration m => m.name,
    _ => throw StateError('Not a class/mixin'),
  };
  TypeParameterList? get typeParameters => switch (this) {
    ClassDeclaration c => c.namePart.typeParameters,
    EnumDeclaration e => e.namePart.typeParameters,
    ClassTypeAlias c => c.typeParameters,
    GenericTypeAlias a => a.typeParameters,
    FunctionTypeAlias a => a.typeParameters,
    MixinDeclaration m => m.typeParameters,
    _ => null,
  };
  Iterable<ClassMember> get members => this is ClassTypeAlias
      ? const []
      : this is EnumDeclaration
      ? (this as EnumDeclaration).body.members
      : (body as ClassBody).members;
  AstNode get body => switch (this) {
    EnumDeclaration e => e.body,
    ClassDeclaration c => c.body,
    MixinDeclaration m => m.body,
    _ => throw StateError('Not a class/mixin'),
  };
  InterfaceElement get typeElement => switch (this) {
    ClassDeclaration c => c.declaredFragment!.element,
    EnumDeclaration e => e.declaredFragment!.element,
    ClassTypeAlias c => c.declaredFragment!.element,
    MixinDeclaration m => m.declaredFragment!.element,
    _ => throw StateError('Not a class/mixin'),
  };
  ExtendsClause? get extendsClause => this is ClassDeclaration
      ? (this as ClassDeclaration).extendsClause
      : null;
  WithClause? get withClause => switch (this) {
    ClassDeclaration c => c.withClause,
    EnumDeclaration e => e.withClause,
    ClassTypeAlias c => c.withClause,
    _ => null,
  };
  MixinOnClause? get onClause =>
      this is MixinDeclaration ? (this as MixinDeclaration).onClause : null;
  ImplementsClause? get implementsClause => switch (this) {
    ClassDeclaration c => c.implementsClause,
    EnumDeclaration e => e.implementsClause,
    ClassTypeAlias c => c.implementsClause,
    MixinDeclaration m => m.implementsClause,
    _ => null,
  };
  Token? get finalKeyword => switch (this) {
    ClassDeclaration c => c.finalKeyword,
    ClassTypeAlias c => c.finalKeyword,
    _ => null,
  };
  Token? get sealedKeyword => switch (this) {
    ClassDeclaration c => c.sealedKeyword,
    ClassTypeAlias c => c.sealedKeyword,
    _ => null,
  };
  Token? get interfaceKeyword => switch (this) {
    ClassDeclaration c => c.interfaceKeyword,
    ClassTypeAlias c => c.interfaceKeyword,
    _ => null,
  };
  Token? get baseKeyword => switch (this) {
    ClassDeclaration c => c.baseKeyword,
    ClassTypeAlias c => c.baseKeyword,
    MixinDeclaration m => m.baseKeyword,
    _ => null,
  };
}

const entityPrefix = 'msbEntity_';
const linkedSdkLibraries = {
  'dart:core',
  'dart:async',
  'dart:collection',
  'dart:math',
  'dart:convert',
  'dart:typed_data',
};
String sdkPrefix(String uri) => '${entityPrefix}sdk_${uri.substring(5)}';
String get sdkImports =>
    "import 'dart:core';\n" +
    linkedSdkLibraries
        .map((uri) => "import '$uri' as ${sdkPrefix(uri)};")
        .join('\n');

String _hash(String text) => sha256.convert(utf8.encode(text)).toString();
Never _reject(String message) => throw FormatException(message);

// Shared by class lowering and the typed AOT dispatch emitter.
FormalParameter unwrapParameter(FormalParameter parameter) =>
    parameter is DefaultFormalParameter ? parameter.parameter : parameter;

String parameterName(FormalParameter parameter) {
  final base = unwrapParameter(parameter);
  if (base is SimpleFormalParameter && base.name?.lexeme == '_') {
    final list = base.thisOrAncestorOfType<FormalParameterList>()!;
    final index = list.parameters.indexWhere((p) => unwrapParameter(p) == base);
    return '${entityPrefix}ignored_$index';
  }
  return parameter.name!.lexeme;
}

class _ParameterSymbols extends RecursiveAstVisitor<void> {
  _ParameterSymbols(this.entities);
  final Map<Element, String> entities;
  @override
  void visitSimpleFormalParameter(SimpleFormalParameter node) {
    if (node.name?.lexeme == '_' && node.declaredFragment != null) {
      entities[node.declaredFragment!.element] = parameterName(node);
    }
    super.visitSimpleFormalParameter(node);
  }
}

String forwardTypeArguments(TypeParameterList? parameters) => parameters == null
    ? ''
    : '<${parameters.typeParameters.map((p) => p.name.lexeme).join(', ')}>';

String forwardArguments(Iterable<FormalParameter> parameters) => parameters
    .map(
      (parameter) => parameter.isNamed
          ? '${parameter.name!.lexeme}: ${parameterName(parameter)}'
          : parameterName(parameter),
    )
    .join(', ');

String dispatchParameterTypes(Iterable<FormalParameter> parameters) {
  final required = <String>[];
  final positional = <String>[];
  final named = <String>[];
  for (final parameter in parameters) {
    final base = unwrapParameter(parameter) as SimpleFormalParameter;
    final type = base.type!.toSource();
    if (parameter.isNamed) {
      named.add(
        '${parameter.isRequiredNamed ? 'required ' : ''}$type ${parameter.name!.lexeme}',
      );
    } else if (parameter.isOptionalPositional) {
      positional.add(type);
    } else {
      required.add(type);
    }
  }
  return [
    ...required,
    if (positional.isNotEmpty) '[${positional.join(', ')}]',
    if (named.isNotEmpty) '{${named.join(', ')}}',
  ].join(', ');
}

class SourceGraph {
  SourceGraph(this.source, this.manifest);
  final String source;
  final Map<String, Object?> manifest;
  String get identity => jsonEncode(manifest);
}

class _Library {
  _Library(this.file, this.uri, this.source, this.unit);
  final File file;
  final String uri;
  // Physical files are archived separately; parts share their owner's identity.
  late String ownerUri = uri;
  final String source;
  final CompilationUnit unit;
  final dependencies = <String>[];
  final parts = <String>[];
}

class _TopProperty {
  _TopProperty(this.ownerUri, this.name, this.symbol, this.member);
  final String ownerUri;
  final String name;
  final String symbol;
  final String member;
  (_Library, FunctionDeclaration)? getter;
  (_Library, FunctionDeclaration)? setter;
}

class _Edit {
  _Edit(this.start, this.end, this.text);
  final int start;
  final int end;
  final String text;
}

// A compound property update can invoke two independently defined accessors.
Set<Element> propertyReferenceElements(SimpleIdentifier node) {
  AstNode target = node;
  final parent = node.parent;
  if (parent is PrefixedIdentifier && parent.identifier == node)
    target = parent;
  if (parent is PropertyAccess && parent.propertyName == node) target = parent;
  final operation = target.parent;
  if (((operation is AssignmentExpression &&
              operation.leftHandSide == target) ||
          (operation is PrefixExpression && operation.operand == target) ||
          (operation is PostfixExpression && operation.operand == target)) &&
      operation is CompoundAssignmentExpression) {
    final elements = <Element>{
      if (operation.readElement != null) operation.readElement!,
      if (operation.writeElement != null) operation.writeElement!,
    };
    if (elements.isNotEmpty) return elements;
  }
  return {if (node.element != null) node.element!};
}

class _References extends RecursiveAstVisitor<void> {
  _References(
    this.entities, {
    this.classes,
    this.libraryUri,
    this.receiver,
    this.owner,
  });
  final Map<Element, String> entities;
  final _Classes? classes;
  final String? libraryUri;
  final String? receiver;
  final InterfaceElement? owner;
  final edits = <_Edit>[];
  final references = <String>{};

  @override
  void visitSimpleFormalParameter(SimpleFormalParameter node) {
    if (node.name != null && classes != null) {
      var text = entities[node.declaredFragment?.element] ?? node.name!.lexeme;
      if (node.type == null) {
        final type = node.declaredFragment!.element.type;
        text = '${classes!.typeText(type, names: entities)} $text';
      }
      if (text != node.name!.lexeme) {
        edits.add(_Edit(node.name!.offset, node.name!.end, text));
      }
    }
    super.visitSimpleFormalParameter(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.returnType == null && classes != null) {
      edits.add(
        _Edit(
          node.name.offset,
          node.name.offset,
          '${classes!.typeText(node.declaredFragment!.element.returnType, names: entities)} ',
        ),
      );
    }
    super.visitFunctionDeclaration(node);
  }

  Element? referencedElement(SimpleIdentifier node) {
    final elements = propertyReferenceElements(node);
    return elements.isEmpty ? node.element : elements.last;
  }

  String? propertySymbol(SimpleIdentifier node) {
    final symbols = {
      for (final element in propertyReferenceElements(node))
        if (entities[element] != null) entities[element]!,
    };
    if (symbols.length > 1) {
      _reject(
        'Distinct property accessors require separate links: ${node.name}',
      );
    }
    references.addAll(symbols);
    return symbols.isEmpty ? null : symbols.single;
  }

  void replace(int start, int end, String symbol) {
    edits.add(_Edit(start, end, symbol));
    references.add(symbol);
  }

  void replaceIdentifier(SimpleIdentifier node, String symbol) {
    final parent = node.parent;
    // A lifted implicit member (or a qualified SDK entity) is an expression,
    // not a single identifier: $field must become ${receiver.field}.
    final interpolation =
        parent is InterpolationExpression && parent.rightBracket == null;
    edits.add(
      _Edit(node.offset, node.end, interpolation ? '{$symbol}' : symbol),
    );
    references.add(symbol);
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    if (receiver != null && node.leftOperand is SuperExpression) {
      final bridge = classes?.superBridge(owner!, node.element);
      if (bridge == null)
        _reject('Unsupported super operator: ${node.toSource()}');
      final negate = node.operator.lexeme == '!=';
      replace(
        node.offset,
        node.operator.end,
        '${negate ? '!' : ''}$receiver.$bridge(',
      );
      node.rightOperand.accept(this);
      edits.add(_Edit(node.end, node.end, ')'));
      return;
    }
    super.visitBinaryExpression(node);
  }

  @override
  void visitPrefixExpression(PrefixExpression node) {
    if (receiver != null && node.operand is SuperExpression) {
      final bridge = classes?.superBridge(owner!, node.element);
      if (bridge == null)
        _reject('Unsupported super unary operator: ${node.toSource()}');
      replace(node.offset, node.end, '$receiver.$bridge()');
      return;
    }
    super.visitPrefixExpression(node);
  }

  @override
  void visitIndexExpression(IndexExpression node) {
    if (receiver != null && node.target is SuperExpression) {
      final write = node.inSetterContext();
      final bridge = write
          ? classes?.declarations[owner]?.indexCellBridge
          : classes?.superBridge(owner!, node.element);
      if (bridge == null)
        _reject('Unsupported super index: ${node.toSource()}');
      if (write) {
        // Keep []/[]= syntax and the instantiated index/value parameter types:
        // a bad dynamic index must fail before evaluating the RHS.
        replace(node.target!.offset, node.target!.end, '$receiver.$bridge');
      } else {
        replace(node.offset, node.leftBracket.end, '$receiver.$bridge(');
        edits.add(_Edit(node.rightBracket.offset, node.end, ')'));
      }
      node.index.accept(this);
      return;
    }
    super.visitIndexExpression(node);
  }

  @override
  void visitAnnotation(Annotation node) {
    super.visitAnnotation(node);
    final element = node.element;
    if (element is ConstructorElement && node.arguments != null) {
      final name = classes?.memberSymbols[element.baseElement] ?? element.name;
      final type = classes!.typeText(element.returnType, names: entities);
      final end = node.arguments!.offset;
      // Annotation.name may include the named constructor in non-generic form.
      // Render the resolved constructor type to retain typedef instantiation.
      edits.removeWhere(
        (edit) => edit.start >= node.name.offset && edit.end <= end,
      );
      replace(node.name.offset, end, '$type${name == 'new' ? '' : '.$name'}');
    }
  }

  @override
  void visitEnumConstantDeclaration(EnumConstantDeclaration node) {
    super.visitEnumConstantDeclaration(node);
    // The selector identifier itself may be unresolved; the enum constant
    // carries the resolved constructor, including generic instantiation.
    final selector = node.arguments?.constructorSelector?.name;
    final symbol = classes?.memberSymbols[node.constructorElement?.baseElement];
    if (selector != null && symbol != null) {
      edits.removeWhere((edit) => edit.start == selector.offset);
      replace(selector.offset, selector.end, symbol);
    }
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (receiver != null && node.target is SuperExpression) {
      final bridge = classes?.superBridge(owner!, node.methodName.element);
      if (bridge == null)
        _reject('Unsupported super invocation: ${node.toSource()}');
      replace(node.target!.offset, node.methodName.end, '$receiver.$bridge');
      node.typeArguments?.accept(this);
      node.argumentList.accept(this);
      return;
    }
    final symbol = entities[node.methodName.element];
    if (symbol != null && node.target != null) {
      // A resolved top-level function with a target must use an import prefix.
      final target = node.target;
      if (target is! SimpleIdentifier ||
          target.element is! PrefixElement ||
          node.isNullAware ||
          node.isCascaded) {
        _reject(
          'Unsupported qualified top-level invocation: ${node.toSource()}',
        );
      }
      replace(target.offset, node.methodName.end, symbol);
      node.typeArguments?.accept(this);
      node.argumentList.accept(this);
      return;
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    if (receiver != null && node.target is SuperExpression) {
      final bridge = classes?.superBridge(
        owner!,
        referencedElement(node.propertyName),
      );
      if (bridge == null)
        _reject('Unsupported super property: ${node.toSource()}');
      replace(node.offset, node.end, '$receiver.$bridge');
      return;
    }
    super.visitPropertyAccess(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    final symbol = propertySymbol(node.identifier);
    if (symbol != null && node.prefix.element is PrefixElement) {
      replace(node.offset, node.end, symbol);
      return;
    }
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final element = referencedElement(node);
    final symbol = propertySymbol(node);
    if (symbol != null) {
      replaceIdentifier(node, symbol);
    } else {
      var member = classes?.memberSymbols[element?.baseElement];
      if (member == null &&
          libraryUri != null &&
          node.name.startsWith('_') &&
          node.isQualified &&
          element == null) {
        member = _privateMember(libraryUri!, node.name);
      }
      final implicit =
          receiver != null &&
          !node.isQualified &&
          element is ExecutableElement &&
          element is! ConstructorElement &&
          !element.isStatic &&
          element.enclosingElement is InterfaceElement;
      final declaring = element?.enclosingElement;
      final staticOwner = declaring is InterfaceElement
          ? classes?.declarations[declaring]
          : null;
      if (!node.isQualified &&
          element is ExecutableElement &&
          element is! ConstructorElement &&
          element.isStatic &&
          staticOwner != null) {
        replaceIdentifier(node, '${staticOwner.symbol}.${member ?? node.name}');
      } else if (implicit) {
        replaceIdentifier(node, '$receiver.${member ?? node.name}');
      } else if (member != null && member != node.name) {
        replaceIdentifier(node, member);
      }
    }
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitTypeParameter(TypeParameter node) {
    final symbol = entities[node.declaredFragment?.element];
    if (symbol != null) replace(node.name.offset, node.name.end, symbol);
    for (final annotation in node.metadata) {
      annotation.accept(this);
    }
    node.bound?.accept(this);
  }

  @override
  void visitNamedType(NamedType node) {
    final parent = node.parent;
    if (node.element is TypeAliasElement &&
        node.type != null &&
        classes != null &&
        (parent is ExtendsClause ||
            parent is WithClause ||
            parent is ImplementsClause ||
            parent is MixinOnClause ||
            (parent is ClassTypeAlias && parent.superclass == node))) {
      // Class compatibility checks must see the real ancestor, including closed
      // class modifiers. A typedef cannot hide an ancestor across modules.
      replace(
        node.offset,
        node.end,
        classes!.typeText(node.type!, names: entities),
      );
      return;
    }
    final symbol = entities[node.element];
    if (symbol != null) replace(node.offset, node.name.end, symbol);
    node.typeArguments?.accept(this);
  }

  @override
  void visitThisExpression(ThisExpression node) {
    if (receiver != null) replace(node.offset, node.end, receiver!);
  }

  @override
  void visitSuperExpression(SuperExpression node) {
    if (receiver != null)
      _reject('Only direct super method calls are currently supported');
  }

  @override
  void visitFieldFormalParameter(FieldFormalParameter node) {
    final symbol = libraryUri == null
        ? node.name.lexeme
        : _privateMember(libraryUri!, node.name.lexeme);
    if (symbol != node.name.lexeme)
      replace(node.name.offset, node.name.end, symbol);
    for (final annotation in node.metadata) {
      annotation.accept(this);
    }
    node.type?.accept(this);
  }
}

String _rewrite(String source, AstNode node, List<_Edit> edits) {
  edits.sort((a, b) => b.start.compareTo(a.start));
  var text = source.substring(node.offset, node.end);
  var previous = node.end;
  for (final edit in edits) {
    if (edit.end > previous || edit.start < node.offset)
      _reject('Overlapping entity rewrites');
    text =
        '${text.substring(0, edit.start - node.offset)}${edit.text}${text.substring(edit.end - node.offset)}';
    previous = edit.start;
  }
  return text;
}

// Resolve all metadata before lowering, including const aliases of pragmas.
// Unknown VM/backend pragmas must not acquire accidental semantics on wrappers.
class _MetadataGuard extends RecursiveAstVisitor<void> {
  @override
  void visitAnnotation(Annotation node) {
    final value = node.elementAnnotation?.computeConstantValue();
    if (value == null)
      _reject('Annotation must resolve to a constant: ${node.toSource()}');
    final type = value.type;
    if (type is InterfaceType &&
        type.element.name == 'pragma' &&
        type.element.library.uri.toString() == 'dart:core') {
      final name = value.getField('name')?.toStringValue();
      if (!{
        'vm:never-inline',
        'vm:prefer-inline',
        'vm:entry-point',
        'wasm:entry-point',
      }.contains(name)) {
        _reject('Unsupported compiler pragma: $name');
      }
    }
    super.visitAnnotation(node);
  }
}

// Collect actual record shapes in the resolved source, including inferred SDK
// expression types and record fields nested inside function/container types.
class _RecordSelectors extends GeneralizingAstVisitor<void> {
  final fields = <String, bool>{};
  final seen = <DartType>{};
  void type(DartType? value) {
    if (value == null || !seen.add(value)) return;
    if (value is RecordType) {
      void field(String name, DartType fieldType) {
        fields[name] =
            (fields[name] ?? false) ||
            fieldType is FunctionType ||
            fieldType is DynamicType ||
            fieldType is TypeParameterType;
        type(fieldType);
      }

      for (var i = 0; i < value.positionalFields.length; i++) {
        field('\$${i + 1}', value.positionalFields[i].type);
      }
      for (final item in value.namedFields) {
        field(item.name, item.type);
      }
    } else if (value is InterfaceType) {
      value.typeArguments.forEach(type);
    } else if (value is TypeParameterType) {
      type(value.bound);
    } else if (value is FunctionType) {
      type(value.returnType);
      for (final parameter in value.formalParameters) {
        type(parameter.type);
      }
      for (final parameter in value.typeParameters) {
        type(parameter.bound);
      }
    }
  }

  @override
  void visitExpression(Expression node) {
    type(node.staticType);
    super.visitExpression(node);
  }

  @override
  void visitTypeAnnotation(TypeAnnotation node) {
    type(node.type);
    super.visitTypeAnnotation(node);
  }
}

// Each root is callable from the dynamic interface, so optimization must retain
// its selector and the native dynamic argument-checking paths. These functions
// are generated infrastructure and are never executed during application boot.
List<Map<String, String>> _dynamicRetentionRoots(
  _Classes classes,
  Iterable<LibraryElement> sdkLibraries,
  Map<String, bool> recordFields,
) {
  final roots = <String, Map<String, String>>{};
  void add(String selector, String expression, int count) {
    final parameters = [
      'dynamic receiver',
      for (var i = 0; i < count; i++) 'dynamic a$i',
    ].join(', ');
    roots['$selector|$expression|$parameters'] = {
      'selector': selector,
      'expression': expression,
      'parameters': parameters,
    };
  }

  void members(InterfaceElement element, bool user) {
    String name(ExecutableElement member) =>
        user ? (classes.memberSymbols[member] ?? member.name!) : member.name!;
    for (final getter in element.getters) {
      if (getter.isStatic || (!user && getter.isPrivate)) continue;
      final key = name(getter);
      add('get:$key', 'receiver.$key', 0);
      // Invocation through a getter must retain the getter's dynamic path too.
      if (getter.returnType is FunctionType ||
          getter.returnType is DynamicType) {
        add('invoke:$key', 'receiver.$key()', 0);
      }
    }
    for (final setter in element.setters) {
      if (setter.isStatic || (!user && setter.isPrivate)) continue;
      final key = name(setter).replaceFirst(RegExp(r'=$'), '');
      add('set:$key', 'receiver.$key = a0', 1);
    }
    for (final method in element.methods) {
      if (method.isStatic || (!user && method.isPrivate)) continue;
      final key =
          method.isOperator &&
              method.name == '-' &&
              method.formalParameters.isEmpty
          ? 'unary-'
          : name(method);
      if (method.isOperator) {
        final expression = switch (key) {
          'unary-' => '-receiver',
          '~' => '~receiver',
          '[]' => 'receiver[a0]',
          '[]=' => 'receiver[a0] = a1',
          _ => 'receiver $key a0',
        };
        add('invoke:$key', expression, method.formalParameters.length);
        continue;
      }
      add('get:$key', 'receiver.$key', 0);
      final arguments = <String>[];
      var count = 0;
      for (final parameter in method.formalParameters) {
        if (parameter.isRequiredNamed) {
          arguments.add('${parameter.name}: a${count++}');
        } else if (parameter.isRequiredPositional) {
          arguments.add('a${count++}');
        }
      }
      final types = method.typeParameters.isEmpty
          ? ''
          : '<${List.filled(method.typeParameters.length, 'dynamic').join(', ')}>';
      add('invoke:$key', 'receiver.$key$types(${arguments.join(', ')})', count);
    }
  }

  for (final entry in recordFields.entries) {
    add('get:${entry.key}', 'receiver.${entry.key}', 0);
    if (entry.value) add('invoke:${entry.key}', 'receiver.${entry.key}()', 0);
  }
  add('invoke:call', 'receiver.call()', 0);
  for (final library in sdkLibraries) {
    for (final element in [
      ...library.classes,
      ...library.enums,
      ...library.mixins,
    ]) {
      members(element, false);
    }
  }
  for (final owner in classes.declarations.values) {
    members(owner.element, true);
  }
  final keys = roots.keys.toList()..sort();
  return [for (final key in keys) roots[key]!];
}

Future<SourceGraph> loadSourceGraph(File entryFile) async {
  final entry = File(entryFile.resolveSymbolicLinksSync());
  final root = entry.parent.uri;
  final libraries = <String, _Library>{};
  final partOwners = <String, _Library>{};
  final foundConfig = await findPackageConfigAndFile(entry.parent);
  final configText = foundConfig?.file.readAsStringSync();
  final packageConfig = foundConfig == null
      ? PackageConfig.empty
      : PackageConfig.parseString(configText!, foundConfig.file.uri);
  final packageRecords = <String, Map<String, Object?>>{};
  final packageInputs = <File, String>{};
  final packageHooks = <File>[];
  final conditionalSources = <String, String>{};
  final conditionalInputs = <File, String>{};
  final collection = AnalysisContextCollectionImpl(
    includedPaths: [entry.path],
    declaredVariables: {'dart.library.io': 'true'},
  );
  final session = collection.contexts.single.currentSession;
  final resolved = <String, ResolvedUnitResult>{};

  void recordPackage(Package package) {
    if (packageRecords.containsKey(package.name)) return;
    if (package.root.scheme != 'file')
      _reject('Only local resolved packages are supported');
    final pubspec = File.fromUri(package.root.resolve('pubspec.yaml'));
    final text = pubspec.readAsStringSync();
    final data = loadYaml(text);
    if (data is! Map || data['name'] != package.name) {
      _reject('Package manifest name mismatch: ${package.name}');
    }
    final flutter = data['flutter'];
    final hook = File.fromUri(package.root.resolve('hook/build.dart'));
    packageHooks.add(hook);
    if ((flutter is Map && flutter['plugin'] != null) || hook.existsSync()) {
      _reject(
        'Native plugin or build hook package is not supported: ${package.name}',
      );
    }
    packageInputs[pubspec] = text;
    packageRecords[package.name] = {
      'name': package.name,
      'version': data['version']?.toString(),
      'language_version': package.languageVersion?.toString(),
      'pubspec_sha256': _hash(text),
    };
  }

  final entryPackage = packageConfig.packageOf(entry.uri);
  if (entryPackage != null && packageConfig.toPackageUri(entry.uri) != null) {
    recordPackage(entryPackage);
  }

  String logicalUri(File file) {
    if (file.path == entry.path) return 'app:entry';
    final uri = file.uri.toString();
    final packageUri = packageConfig.toPackageUri(file.uri);
    if (packageUri != null) {
      recordPackage(packageConfig[packageUri.pathSegments.first]!);
      return packageUri.toString();
    }
    if (uri.startsWith(root.toString())) {
      return 'app:${uri.substring(root.toString().length)}';
    }
    _reject(
      'Library escapes entry source root or configured package libraries: ${file.path}',
    );
  }

  Future<void> discover(File file, {_Library? partOwner}) async {
    file = File(file.resolveSymbolicLinksSync());
    if (partOwner != null) {
      final previous = partOwners[file.path];
      if (previous != null && previous.file.path != partOwner.file.path) {
        _reject('Part file is included by multiple owners: ${file.path}');
      }
      partOwners[file.path] = partOwner;
    }
    if (libraries.containsKey(file.path)) return;
    final uri = logicalUri(file);
    final source = file.readAsStringSync();
    final parsed = parseString(content: source, throwIfDiagnostics: false);
    if (parsed.errors.isNotEmpty)
      _reject('Invalid Dart source in $uri: ${parsed.errors}');
    final library = _Library(file, uri, source, parsed.unit);
    libraries[file.path] = library; // Insert before traversal to handle cycles.
    final result = await session.getResolvedUnit(file.path);
    if (result is! ResolvedUnitResult || result.content != source) {
      _reject('Source resolution failed or changed during analysis: $uri');
    }
    resolved[uri] = result;
    for (
      var token = parsed.unit.beginToken;
      !token.isEof;
      token = token.next!
    ) {
      if (token.lexeme.startsWith(entityPrefix) ||
          token.lexeme.startsWith('simurgh')) {
        _reject('Reserved generated identifier in $uri: ${token.lexeme}');
      }
    }
    for (final declaration in parsed.unit.declarations) {
      if (declaration is! FunctionDeclaration &&
          declaration is! ClassDeclaration &&
          declaration is! ClassTypeAlias &&
          declaration is! EnumDeclaration &&
          declaration is! GenericTypeAlias &&
          declaration is! FunctionTypeAlias &&
          declaration is! MixinDeclaration &&
          declaration is! TopLevelVariableDeclaration) {
        _reject(
          'Library $uri: classes, fields and extensions require layout/dependency support',
        );
      }
    }
    for (final directive in result.unit.directives) {
      if (directive is LibraryDirective && directive.metadata.isEmpty) continue;
      if (directive is PartOfDirective && directive.metadata.isEmpty) {
        if (!partOwners.containsKey(file.path)) {
          _reject('Part cannot be an entrypoint or imported library: $uri');
        }
        continue;
      }
      if (directive is! ImportDirective &&
          directive is! ExportDirective &&
          directive is! PartDirective) {
        _reject('Unsupported library directive in $uri');
      }
      final isPart = directive is PartDirective;
      if (directive.metadata.isNotEmpty ||
          (directive is ImportDirective && directive.deferredKeyword != null)) {
        _reject(
          'Annotated or deferred imports/exports are not implemented: $uri',
        );
      }
      String? target = (directive as UriBasedDirective).uri.stringValue;
      if (directive is NamespaceDirective &&
          directive.configurations.isNotEmpty) {
        for (final configuration in directive.configurations) {
          if (!{
            'dart.library.io',
            'dart.library.html',
          }.contains(configuration.name.toSource())) {
            _reject('Unsupported conditional environment in $uri');
          }
        }
        for (final candidate in [
          directive.uri.stringValue,
          ...directive.configurations.map(
            (configuration) => configuration.uri.stringValue,
          ),
        ]) {
          final candidateUri = candidate == null
              ? null
              : Uri.tryParse(candidate);
          if (candidateUri == null) {
            _reject('Invalid conditional import/export URI in $uri');
          }
          if (candidateUri.scheme == 'dart') continue;
          File candidateFile;
          if (candidateUri.scheme == 'package') {
            final location = packageConfig.resolve(candidateUri);
            if (location == null || location.scheme != 'file') {
              _reject('Unresolved conditional package import: $candidate');
            }
            candidateFile = File(
              File.fromUri(location).resolveSymbolicLinksSync(),
            );
            if (packageConfig.toPackageUri(candidateFile.uri) != candidateUri) {
              _reject(
                'Conditional package import escapes its library root: $candidate',
              );
            }
          } else if (!candidateUri.hasScheme &&
              !candidateUri.hasAuthority &&
              !candidateUri.hasQuery &&
              !candidateUri.hasFragment &&
              !candidateUri.path.startsWith('/') &&
              candidateUri.path.endsWith('.dart')) {
            candidateFile = File(
              File.fromUri(
                file.uri.resolveUri(candidateUri),
              ).resolveSymbolicLinksSync(),
            );
          } else {
            _reject('Unsupported conditional import/export URI: $candidate');
          }
          final candidateSource = candidateFile.readAsStringSync();
          conditionalSources[logicalUri(candidateFile)] = candidateSource;
          conditionalInputs[candidateFile] = candidateSource;
        }
        final selected = switch (directive) {
          ImportDirective() => directive.libraryImport?.importedLibrary,
          ExportDirective() => directive.libraryExport?.exportedLibrary,
        };
        if (selected == null) {
          _reject('Unresolved conditional import/export in $uri');
        }
        final selectedUri = selected.uri;
        if (selectedUri.scheme == 'dart') {
          target = selectedUri.toString();
        } else {
          final sourceUri = selected.firstFragment.source.uri;
          final resolvedUri = sourceUri.scheme == 'package'
              ? packageConfig.resolve(sourceUri)
              : sourceUri;
          if (resolvedUri == null || resolvedUri.scheme != 'file') {
            _reject('Unsupported conditional import/export target: $sourceUri');
          }
          final selectedFile = File(
            File.fromUri(resolvedUri).resolveSymbolicLinksSync(),
          );
          if (sourceUri.scheme == 'package' &&
              packageConfig.toPackageUri(selectedFile.uri) != sourceUri) {
            _reject(
              'Conditional package import escapes its library root: $sourceUri',
            );
          }
          library.dependencies.add(logicalUri(selectedFile));
          await discover(selectedFile);
          continue;
        }
      }
      if (linkedSdkLibraries.contains(target)) {
        if (isPart)
          _reject('Part must resolve to a local Dart source file: $target');
        library.dependencies.add(target!);
        continue;
      }
      final parsedUri = target == null ? null : Uri.tryParse(target);
      if (parsedUri?.scheme == 'package') {
        final resolved = packageConfig.resolve(parsedUri!);
        if (resolved == null || resolved.scheme != 'file') {
          _reject('Unresolved local package import: $target');
        }
        final dependency = File(
          File.fromUri(resolved).resolveSymbolicLinksSync(),
        );
        if (packageConfig.toPackageUri(dependency.uri) != parsedUri) {
          _reject(
            'Package import escapes or aliases its configured library root: $target',
          );
        }
        recordPackage(packageConfig[parsedUri.pathSegments.first]!);
        (isPart ? library.parts : library.dependencies).add(
          logicalUri(dependency),
        );
        await discover(dependency, partOwner: isPart ? library : null);
        continue;
      }
      if (parsedUri == null ||
          parsedUri.hasScheme ||
          parsedUri.hasAuthority ||
          parsedUri.hasQuery ||
          parsedUri.hasFragment ||
          parsedUri.path.startsWith('/') ||
          !parsedUri.path.endsWith('.dart')) {
        _reject('Only local relative Dart imports/exports supported: $target');
      }
      final dependency = File.fromUri(file.uri.resolveUri(parsedUri));
      final canonical = File(dependency.resolveSymbolicLinksSync());
      (isPart ? library.parts : library.dependencies).add(
        logicalUri(canonical),
      );
      await discover(canonical, partOwner: isPart ? library : null);
    }
  }

  try {
    await discover(entry);
  } catch (_) {
    await collection.dispose();
    rethrow;
  }
  final sorted = libraries.values.toList()
    ..sort((a, b) => a.uri.compareTo(b.uri));
  try {
    for (final library in sorted) {
      final result = resolved[library.uri]!;
      final errors = result.diagnostics.where(
        (d) => d.severity == Severity.error,
      );
      if (errors.isNotEmpty)
        _reject('Static source errors in ${library.uri}: ${errors.join('; ')}');
      final ownerUri = result.libraryElement.uri;
      final ownerFileUri = ownerUri.scheme == 'package'
          ? packageConfig.resolve(ownerUri) ?? ownerUri
          : ownerUri;
      if (ownerFileUri.scheme != 'file')
        _reject('Unsupported part owner: $ownerUri');
      final ownerPath = File.fromUri(ownerFileUri).resolveSymbolicLinksSync();
      final owner = libraries[ownerPath];
      if (owner == null)
        _reject('Part owner is outside the discovered source graph: $ownerUri');
      library.ownerUri = owner.uri;
      resolved[library.uri] = result;
    }
    final languageVersions = <String, String>{};
    final versionNumbers = <int>[];
    for (final library in sorted) {
      final declaredOwner = partOwners[library.file.path];
      if (declaredOwner == null
          ? library.ownerUri != library.uri
          : library.ownerUri != declaredOwner.ownerUri ||
                library.ownerUri == library.uri) {
        _reject(
          'Part ownership does not match analyzer resolution: ${library.uri}',
        );
      }
      final v = resolved[library.uri]!.libraryElement.languageVersion.effective;
      languageVersions[library.ownerUri] = '${v.major}.${v.minor}';
      versionNumbers.add(v.major * 1000 + v.minor);
    }
    versionNumbers.sort();
    final latest = versionNumbers.last;
    final languageVersion = '${latest ~/ 1000}.${latest % 1000}';
    final recordSelectors = _RecordSelectors();
    for (final unit in resolved.values) {
      unit.unit.accept(recordSelectors);
      unit.unit.accept(_MetadataGuard());
    }
    final entities = <Element, String>{};
    for (final unit in resolved.values) {
      unit.unit.accept(_ParameterSymbols(entities));
    }
    final sdkLibraries = <LibraryElement>[];
    for (final uri in linkedSdkLibraries) {
      final result = await session.getLibraryByUri(uri);
      if (result is! LibraryElementResult)
        _reject('Cannot resolve SDK library: $uri');
      final library = result.element;
      sdkLibraries.add(library);
      for (final entry in library.exportNamespace.definedNames2.entries) {
        final element = entry.value;
        final name = entry.key.replaceFirst(RegExp(r'=$'), '');
        // Preserve existing primitive/Future spellings and implicit core calls.
        final bare =
            (uri == 'dart:core' &&
                (element is! InterfaceElement ||
                    const {
                      'int',
                      'double',
                      'num',
                      'bool',
                      'String',
                      'Object',
                      'Null',
                    }.contains(name))) ||
            (name == 'Future' &&
                element.library?.uri.toString() == 'dart:async');
        entities.putIfAbsent(
          element,
          () => bare ? name : '${sdkPrefix(uri)}.$name',
        );
      }
    }
    final records = <String, Map<String, Object?>>{};
    final classes = _Classes(entities, records);
    for (final library in sorted) {
      for (final declaration in resolved[library.uri]!.unit.declarations.where(
        (node) =>
            node is ClassDeclaration ||
            node is ClassTypeAlias ||
            node is EnumDeclaration ||
            node is MixinDeclaration,
      )) {
        classes.register(library, declaration);
      }
    }
    final aliases = <(_Library, CompilationUnitMember, TypeAliasElement)>[];
    for (final library in sorted) {
      for (final declaration in resolved[library.uri]!.unit.declarations) {
        if (declaration is! GenericTypeAlias &&
            declaration is! FunctionTypeAlias)
          continue;
        final element =
            declaration.declaredFragment!.element as TypeAliasElement;
        final id = _hash('${library.ownerUri}::typedef::${element.name}');
        final symbol = '${entityPrefix}alias_$id';
        entities[element] = symbol;
        for (var index = 0; index < element.typeParameters.length; index++) {
          entities[element.typeParameters[index]] =
              '${entityPrefix}type_${_hash('$id::$index')}';
        }
        records[symbol] = {
          'library': library.ownerUri,
          'name': element.name,
          'entity': id,
          'kind': 'typedef',
        };
        aliases.add((library, declaration, element));
      }
    }
    final properties = <String, _TopProperty>{};
    for (final library in sorted) {
      for (final declaration
          in resolved[library.uri]!.unit.declarations
              .whereType<FunctionDeclaration>()) {
        final name = declaration.name.lexeme;
        if (declaration.isGetter || declaration.isSetter) {
          if (declaration.externalKeyword != null ||
              declaration.functionExpression.body is EmptyFunctionBody) {
            _reject('Unsupported top-level accessor declaration: $name');
          }
          final propertyId = _hash('${library.ownerUri}::property::$name');
          final adapter = '${entityPrefix}property_$propertyId';
          final property = properties.putIfAbsent(adapter, () {
            records[adapter] = {
              'library': library.ownerUri,
              'name': name,
              'entity': propertyId,
              'kind': 'class',
              'generated': 'top-accessor-adapter',
            };
            return _TopProperty(
              library.ownerUri,
              name,
              adapter,
              _privateMember(library.ownerUri, name),
            );
          });
          final isGetter = declaration.isGetter;
          if (isGetter ? property.getter != null : property.setter != null) {
            _reject(
              'Duplicate top-level accessor in ${library.ownerUri}: $name',
            );
          }
          if (isGetter) {
            property.getter = (library, declaration);
          } else {
            property.setter = (library, declaration);
          }
          final kind = isGetter ? 'getter' : 'setter';
          final id = _hash('${library.ownerUri}::top-$kind::$name');
          final helper = '${entityPrefix}top_${kind}_$id';
          final element = declaration.declaredFragment?.element;
          if (element == null) _reject('Unresolved top-level accessor: $name');
          entities[element] = '$adapter.${property.member}';
          records[helper] = {
            'library': library.ownerUri,
            'name': '$kind $name',
            'entity': id,
            'kind': 'top-$kind',
            'owner': adapter,
          };
          continue;
        }
        final id = _hash('${library.ownerUri}::function::$name');
        final symbol = library.ownerUri == 'app:entry' && name == 'main'
            ? 'main'
            : '$entityPrefix$id';
        final element = declaration.declaredFragment?.element;
        if (element == null || records.containsKey(symbol))
          _reject('Invalid or duplicate entity in ${library.uri}: $name');
        entities[element] = symbol;
        records[symbol] = {
          'library': library.ownerUri,
          'name': name,
          'entity': id,
          if (declaration.functionExpression.body.isAsynchronous)
            'async_return_supported': supportsAsyncReturn(element.returnType),
        };
      }
    }
    for (final library in sorted) {
      for (final declaration
          in resolved[library.uri]!.unit.declarations
              .whereType<TopLevelVariableDeclaration>()) {
        for (final variable in declaration.variables.variables) {
          final element =
              variable.declaredFragment!.element as TopLevelVariableElement;
          final name = variable.name.lexeme;
          final id = _hash('${library.ownerUri}::global::$name');
          final symbol = '${entityPrefix}global_$id';
          entities[element] = symbol;
          if (element.getter != null) entities[element.getter!] = symbol;
          if (element.setter != null) entities[element.setter!] = symbol;
          records[symbol] = {
            'library': library.ownerUri,
            'name': name,
            'entity': id,
            'kind': 'global',
          };
        }
      }
    }
    await classes.loadSdkAncestors(session);
    classes.prepare();
    classes.prepareInterfaceBridges();
    final source = StringBuffer('// @dart=$languageVersion\n$sdkImports\n');
    // Expand the target type, but retain the alias binder and declaration.
    // Raw constructor tear-offs must remain generic rather than instantiate to bounds.
    for (final (library, declaration, element) in aliases) {
      final visitor = _References(
        entities,
        classes: classes,
        libraryUri: library.ownerUri,
      );
      for (final annotation in declaration.metadata) {
        annotation.accept(visitor);
      }
      final parameters = declaration.typeParameters;
      parameters?.accept(visitor);
      final generics = parameters == null
          ? ''
          : _rewrite(
              library.source,
              parameters,
              visitor.edits
                  .where(
                    (e) =>
                        e.start >= parameters.offset && e.end <= parameters.end,
                  )
                  .toList(),
            );
      source.writeln(
        '${declaration.metadata.map((a) => _rewrite(library.source, a, visitor.edits.where((e) => e.start >= a.offset && e.end <= a.end).toList())).join('\n')}\ntypedef ${entities[element]}$generics = ${classes.typeText(element.aliasedType)};',
      );
    }

    for (final property in properties.values) {
      final wrapper = StringBuffer('class ${property.symbol} {\n');
      for (final (kind, entry) in [
        ('getter', property.getter),
        ('setter', property.setter),
      ]) {
        if (entry == null) continue;
        final (library, declaration) = entry;
        final element = declaration.declaredFragment!.element;
        final id = _hash('${property.ownerUri}::top-$kind::${property.name}');
        final helper = '${entityPrefix}top_${kind}_$id';
        final visitor = _References(
          entities,
          classes: classes,
          libraryUri: property.ownerUri,
        );
        for (final annotation in declaration.metadata) {
          annotation.accept(visitor);
        }
        declaration.returnType?.accept(visitor);
        declaration.functionExpression.accept(visitor);
        final resultType = classes.typeText(element.returnType);
        final parameters = declaration.functionExpression.parameters;
        final annotations = declaration.metadata
            .map(
              (annotation) => _rewrite(
                library.source,
                annotation,
                visitor.edits
                    .where(
                      (edit) =>
                          edit.start >= annotation.offset &&
                          edit.end <= annotation.end,
                    )
                    .toList(),
              ),
            )
            .join('\n');
        if (annotations.isNotEmpty) wrapper.writeln(annotations);
        if (kind == 'getter') {
          wrapper.writeln(
            'static $resultType get ${property.member} => $helper();',
          );
        } else {
          if (parameters == null || parameters.parameters.length != 1) {
            _reject(
              'Top-level setter requires one parameter: ${property.name}',
            );
          }
          final args = forwardArguments(parameters.parameters);
          final parameterText = _rewrite(
            library.source,
            parameters,
            visitor.edits
                .where(
                  (e) =>
                      e.start >= parameters.offset && e.end <= parameters.end,
                )
                .toList(),
          );
          wrapper.writeln(
            'static set ${property.member}$parameterText { $helper($args); }',
          );
        }
        final edits = [
          ...visitor.edits,
          _Edit(
            declaration.propertyKeyword!.offset,
            declaration.name.end,
            '${declaration.returnType == null ? '$resultType ' : ''}$helper${kind == 'getter' ? '()' : ''}',
          ),
        ];
        records[helper]!['references'] = visitor.references.toList()..sort();
        source.writeln(_rewrite(library.source, declaration, edits));
      }
      wrapper.writeln('}');
      source.writeln(wrapper);
    }

    for (final library in sorted) {
      for (final declaration
          in resolved[library.uri]!.unit.declarations
              .whereType<FunctionDeclaration>()) {
        if (declaration.isGetter || declaration.isSetter) continue;
        final symbol = entities[declaration.declaredFragment!.element]!;
        final visitor = _References(
          entities,
          classes: classes,
          libraryUri: library.ownerUri,
        );
        if (symbol == 'main' && declaration.returnType != null) {
          visitor.replace(
            declaration.returnType!.offset,
            declaration.returnType!.end,
            classes.typeText(declaration.declaredFragment!.element.returnType),
          );
        } else {
          declaration.returnType?.accept(visitor);
        }
        for (final annotation in declaration.metadata) {
          annotation.accept(visitor);
        }
        declaration.functionExpression.accept(visitor);
        final edits = [
          ...visitor.edits,
          _Edit(
            declaration.name.offset,
            declaration.name.end,
            '${declaration.returnType == null ? '${classes.typeText(declaration.declaredFragment!.element.returnType)} ' : ''}$symbol',
          ),
        ];
        final text = _rewrite(library.source, declaration, edits);
        records[symbol]!['references'] = visitor.references.toList()..sort();
        source.writeln(text);
      }
    }
    for (final library in sorted) {
      for (final declaration
          in resolved[library.uri]!.unit.declarations
              .whereType<TopLevelVariableDeclaration>()) {
        final visitor = _References(
          entities,
          classes: classes,
          libraryUri: library.ownerUri,
        );
        declaration.accept(visitor);
        final edits = [...visitor.edits];
        for (final variable in declaration.variables.variables) {
          final symbol = entities[variable.declaredFragment!.element]!;
          edits.add(_Edit(variable.name.offset, variable.name.end, symbol));
          records[symbol]!['references'] = visitor.references.toList()..sort();
        }
        if (declaration.variables.type == null) {
          if (declaration.externalKeyword != null) {
            _reject('External globals are not implemented');
          }
          final variables = declaration.variables;
          final modifiers =
              '${variables.isLate ? 'late ' : ''}'
              '${variables.isConst
                  ? 'const '
                  : variables.isFinal
                  ? 'final '
                  : ''}';
          for (final variable in variables.variables) {
            final element = variable.declaredFragment!.element;
            final inferred = classes.typeText(element.type);
            final symbol = entities[element]!;
            records[symbol]!['inferred_type'] = inferred;
            source.writeln(
              '${declaration.metadata.map((a) => _rewrite(library.source, a, edits.where((e) => e.start >= a.offset && e.end <= a.end).toList())).join('\n')}\n$modifiers$inferred ${_rewrite(library.source, variable, edits.where((e) => e.start >= variable.offset && e.end <= variable.end).toList())};',
            );
          }
        } else {
          source.writeln(_rewrite(library.source, declaration, edits));
        }
      }
    }
    source.write(classes.lower());
    // A coherent graph is required: don't bind mixed versions of source files.
    for (final library in sorted) {
      if (library.file.readAsStringSync() != library.source)
        _reject('Source graph changed during compilation');
    }
    for (final input in conditionalInputs.entries) {
      if (input.key.readAsStringSync() != input.value) {
        _reject('Conditional source changed during compilation');
      }
    }
    if (foundConfig != null &&
        foundConfig.file.readAsStringSync() != configText) {
      _reject('Package configuration changed during compilation');
    }
    for (final input in packageInputs.entries) {
      if (input.key.readAsStringSync() != input.value) {
        _reject('Package manifest changed during compilation');
      }
    }
    if (packageHooks.any((hook) => hook.existsSync())) {
      _reject('Native build hook appeared during compilation');
    }
    final packageNames = packageRecords.keys.toList()..sort();
    return SourceGraph(source.toString(), {
      'schema': 1,
      'entry': 'app:entry',
      'entry_package_uri': packageConfig.toPackageUri(entry.uri)?.toString(),
      'language_version': languageVersion,
      'library_language_versions': languageVersions,
      'packages': {for (final name in packageNames) name: packageRecords[name]},
      if (conditionalSources.isNotEmpty)
        'conditional_sources': {
          for (final name in (conditionalSources.keys.toList()..sort()))
            if (!sorted.any((library) => library.uri == name))
              name: {
                'source': conditionalSources[name],
                'source_sha256': _hash(conditionalSources[name]!),
              },
        },
      'libraries': {
        for (final library in sorted)
          library.uri: {
            'source': library.source,
            'source_sha256': _hash(library.source),
            'owner': library.ownerUri,
            'parts': library.parts.toSet().toList()..sort(),
            'dependencies': library.dependencies.toSet().toList()..sort(),
          },
      },
      'entities': records,
      'classes': classes.manifest,
      'sdk_libraries': linkedSdkLibraries.toList(),
      // Retain legal SDK inheritance/implementation contracts before patches
      // first use them. Analyzer still enforces original source restrictions.
      'sdk_superclasses': [
        for (final element in entities.keys.whereType<InterfaceElement>())
          if (classes.sdkSuperclass(element))
            {'library': element.library.uri.toString(), 'class': element.name},
      ],
      'sdk_mixins': [
        for (final element in entities.keys.whereType<InterfaceElement>())
          if (classes.sdkMixin(element))
            {'library': element.library.uri.toString(), 'class': element.name},
      ],
      'sdk_interfaces': [
        for (final element in entities.keys.whereType<InterfaceElement>())
          if (classes.sdkInterface(element))
            {'library': element.library.uri.toString(), 'class': element.name},
      ],
      'dynamic_retention_roots': _dynamicRetentionRoots(
        classes,
        sdkLibraries,
        recordSelectors.fields,
      ),
    });
  } finally {
    await collection.dispose();
  }
}
