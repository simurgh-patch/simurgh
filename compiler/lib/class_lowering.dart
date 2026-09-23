part of 'source_graph.dart';

const _receiver = 'msbEntity_receiver';
String _operatorName(MethodDeclaration method) =>
    method.isOperator &&
        method.name.lexeme == '-' &&
        method.parameters!.parameters.isEmpty
    ? 'unary-'
    : method.name.lexeme;

String _privateMember(String library, String name) => name.startsWith('_')
    ? '${entityPrefix}member_${_hash('$library::private::$name')}'
    : name;

class _Class {
  _Class(this.library, this.node, this.element, this.symbol);
  final _Library library;
  final CompilationUnitMember node;
  final InterfaceElement element;
  final String symbol;
  final bridges = <Element, String>{};
  final privateInterfaceStubs = <Element, String>{};
  String? indexCellBridge;
  final bridgeStubs = <MapEntry<Element, String>>[];
  final indexCellStubs = <_Class>[];
}

class _Classes {
  _Classes(this.entities, this.records);
  final Map<Element, String> entities;
  final Map<String, Map<String, Object?>> records;
  final declarations = <InterfaceElement, _Class>{};
  final sdkAncestors = <InterfaceElement, _Class>{};
  final fieldOwners = <Element, _Class>{};
  final memberSymbols = <Element, String>{};
  final methods = <Element, MethodDeclaration>{};
  final methodOwners = <Element, _Class>{};
  final helpers = <Element, String>{};
  final manifest = <String, Object?>{};

  void register(_Library library, CompilationUnitMember node) {
    if ((node is ClassDeclaration &&
            (node.namePart is! NameWithTypeParameters ||
                node.nativeClause != null)) ||
        node.metadata.isNotEmpty) {
      _reject(
        'Annotated/native classes or primary constructors are not implemented',
      );
    }
    final element = node.typeElement;
    final name = node.typeName.lexeme;
    final id = _hash('${library.ownerUri}::class::$name');
    // Runtime display-name ABI: identity remains the library/class hash.
    final symbol = '${entityPrefix}class_${id}__$name';
    entities[element] = symbol;
    for (var index = 0; index < element.typeParameters.length; index++) {
      entities[element.typeParameters[index]] =
          '${entityPrefix}type_${_hash('$id::$index')}';
    }
    declarations[element] = _Class(library, node, element, symbol);
    records[symbol] = {
      'library': library.ownerUri,
      'name': name,
      'entity': id,
      'kind': 'class',
    };
  }

  _References visitor(
    _Class owner, {
    String? receiver,
    Map<Element, String> substitutions = const {},
  }) => _References(
    {...entities, ...substitutions},
    classes: this,
    libraryUri: owner.library.ownerUri,
    receiver: receiver,
    owner: owner.element,
  );

  String text(
    _Class owner,
    AstNode node, {
    String? receiver,
    List<_Edit>? extra,
    Map<Element, String> substitutions = const {},
  }) {
    final refs = visitor(
      owner,
      receiver: receiver,
      substitutions: substitutions,
    );
    node.accept(refs);
    return _rewrite(owner.library.source, node, [...refs.edits, ...?extra]);
  }

  String typeText(DartType type, {Map<Element, String>? names}) {
    final symbols = names ?? entities;
    final suffix = type.nullabilitySuffix == NullabilitySuffix.question
        ? '?'
        : '';
    if (type is TypeParameterType)
      return '${symbols[type.element] ?? type.element.name}$suffix';
    if (type is InterfaceType) {
      final name = symbols[type.element] ?? type.element.name!;
      final arguments = type.typeArguments.isEmpty
          ? ''
          : '<${type.typeArguments.map((t) => typeText(t, names: symbols)).join(', ')}>';
      return '$name$arguments$suffix';
    }
    if (type is FunctionType) {
      final required = <String>[];
      final optional = <String>[];
      final named = <String>[];
      for (final parameter in type.formalParameters) {
        final value = typeText(parameter.type, names: symbols);
        if (parameter.isNamed) {
          named.add(
            '${parameter.isRequiredNamed ? 'required ' : ''}$value ${parameter.name}',
          );
        } else if (parameter.isOptionalPositional) {
          optional.add(value);
        } else {
          required.add(value);
        }
      }
      final parameters = [
        ...required,
        if (optional.isNotEmpty) '[${optional.join(', ')}]',
        if (named.isNotEmpty) '{${named.join(', ')}}',
      ].join(', ');
      final generics = type.typeParameters.isEmpty
          ? ''
          : '<${type.typeParameters.map((p) => '${p.name}${p.bound == null ? '' : ' extends ${typeText(p.bound!, names: symbols)}'}').join(', ')}>';
      return '${typeText(type.returnType, names: symbols)} Function$generics($parameters)$suffix';
    }
    if (type is DynamicType || type is VoidType || type is NeverType)
      return type.getDisplayString();
    _reject(
      'Unsupported inherited type substitution: ${type.getDisplayString()}',
    );
  }

  Map<Element, String> superSubstitutions(_Class owner, _Class parent) {
    final instantiated = owner.element.allSupertypes.firstWhere(
      (type) => type.element == parent.element,
    );
    return {
      for (var i = 0; i < parent.element.typeParameters.length; i++)
        parent.element.typeParameters[i]: typeText(
          instantiated.typeArguments[i],
        ),
    };
  }

  bool sdkInterface(InterfaceElement element) =>
      element is ClassElement &&
      element.isImplementableOutside &&
      !element.isPrivate &&
      linkedSdkLibraries.contains(element.library.uri.toString()) &&
      entities.containsKey(element);

  bool sdkSuperclass(InterfaceElement element) =>
      element is ClassElement &&
      element.isExtendableOutside &&
      !element.isPrivate &&
      linkedSdkLibraries.contains(element.library.uri.toString()) &&
      entities.containsKey(element);

  bool sdkMixin(InterfaceElement element) =>
      ((element is ClassElement && element.isMixableOutside) ||
          element is MixinElement) &&
      !element.isPrivate &&
      linkedSdkLibraries.contains(element.library.uri.toString()) &&
      entities.containsKey(element);

  Future<void> loadSdkAncestors(AnalysisSession session) async {
    final libraries = <LibraryElement, ResolvedLibraryResult>{};
    for (final owner in declarations.values) {
      for (final type in owner.element.allSupertypes) {
        final element = type.element;
        if (!element.library.uri.isScheme('dart') ||
            sdkAncestors.containsKey(element))
          continue;
        var library = libraries[element.library];
        if (library == null) {
          final result = await session.getResolvedLibraryByElement(
            element.library,
          );
          if (result is! ResolvedLibraryResult)
            _reject('Cannot resolve SDK superclass: ${element.name}');
          libraries[element.library] = library = result;
        }
        final declaration = library.getFragmentDeclaration(
          element.firstFragment,
        );
        if (declaration == null ||
            (declaration.node is! ClassDeclaration &&
                declaration.node is! MixinDeclaration))
          _reject('Unsupported SDK superclass declaration: ${element.name}');
        final unit = declaration.resolvedUnit!;
        final source = _Library(
          File(unit.path),
          element.library.uri.toString(),
          unit.content,
          unit.unit,
        );
        final parent = _Class(
          source,
          declaration.node as CompilationUnitMember,
          element,
          entities[element] ?? element.name!,
        );
        sdkAncestors[element] = parent;
        for (final accessor in <PropertyAccessorElement>[
          ...element.getters,
          ...element.setters,
        ]) {
          if (accessor.isStatic ||
              accessor.isPrivate ||
              !accessor.isOriginVariable)
            continue;
          fieldOwners[accessor] = parent;
          memberSymbols[accessor] = accessor.name!.replaceFirst(
            RegExp(r'=$'),
            '',
          );
        }
        for (final member
            in parent.node.body.members.whereType<MethodDeclaration>()) {
          final method = member.declaredFragment!.element;
          if (method.isStatic || method.isPrivate) continue;
          methods[method] = member;
          methodOwners[method] = parent;
          memberSymbols[method] = member.name.lexeme;
        }
      }
    }
  }

  void prepare() {
    for (final owner in declarations.values) {
      final supertype = owner.element.supertype?.element;
      if (supertype != null &&
          !(supertype.library.uri.toString() == 'dart:core' &&
              supertype.name == 'Object') &&
          !declarations.containsKey(supertype) &&
          !sdkSuperclass(supertype)) {
        _reject('Superclass must be a supported program or public SDK class');
      }
      for (final mixin in owner.element.mixins) {
        if (!declarations.containsKey(mixin.element) &&
            !sdkMixin(mixin.element)) {
          _reject('Mixins must be supported program or public SDK types');
        }
      }
      if (owner.element is MixinElement) {
        for (final constraint
            in (owner.element as MixinElement).superclassConstraints) {
          if (!constraint.isDartCoreObject &&
              !declarations.containsKey(constraint.element) &&
              !sdkSuperclass(constraint.element) &&
              !sdkInterface(constraint.element)) {
            _reject(
              'Mixin constraints must be supported program or public SDK classes',
            );
          }
        }
      }
      for (final interface in owner.element.interfaces) {
        if (!declarations.containsKey(interface.element) &&
            !sdkInterface(interface.element)) {
          _reject('Interfaces must be supported program or public SDK classes');
        }
      }
      for (final member in owner.node.body.members) {
        if (member is FieldDeclaration) {
          if (member.metadata.isNotEmpty ||
              member.externalKeyword != null ||
              member.covariantKeyword != null) {
            _reject('Annotated/external/covariant fields are not supported');
          }
          for (final variable in member.fields.variables) {
            final field = owner.element.getField(variable.name.lexeme)!;
            final name = _privateMember(
              owner.library.ownerUri,
              variable.name.lexeme,
            );
            memberSymbols[field] = name;
            for (final accessor in [field.getter, field.setter]) {
              if (accessor == null) continue;
              memberSymbols[accessor] = name;
              if (!field.isStatic) fieldOwners[accessor] = owner;
            }
          }
        } else if (member is ConstructorDeclaration) {
          if (member.externalKeyword != null || member.metadata.isNotEmpty) {
            _reject('External or annotated constructors are not implemented');
          }
          for (final formal in member.parameters.parameters) {
            final param = unwrapParameter(formal);
            if (param is! SimpleFormalParameter &&
                param is! FieldFormalParameter &&
                param is! SuperFormalParameter) {
              _reject(
                'Only simple, field or super constructor parameters supported',
              );
            }
            if (param is FieldFormalParameter) {
              memberSymbols[param.declaredFragment!.element] = _privateMember(
                owner.library.ownerUri,
                param.name.lexeme,
              );
            }
          }
          if (member.name != null) {
            memberSymbols[member.declaredFragment!.element] = _privateMember(
              owner.library.ownerUri,
              member.name!.lexeme,
            );
          }
        } else if (member is MethodDeclaration) {
          if (member.externalKeyword != null ||
              member.body.isGenerator ||
              member.metadata.any(
                (a) => a.name.toSource() != 'override' || a.arguments != null,
              )) {
            _reject(
              'Unsupported instance method kind or signature: ${member.name.lexeme}',
            );
          }
          final resolvedReturn = member.declaredFragment!.element.returnType;
          if (member.body.isAsynchronous &&
              resolvedReturn is! DynamicType &&
              !(resolvedReturn is InterfaceType &&
                  resolvedReturn.isDartAsyncFuture)) {
            _reject('Async methods require a Future return type');
          }
          for (final formal
              in member.parameters?.parameters ?? <FormalParameter>[]) {
            final param = unwrapParameter(formal);
            if (param is! SimpleFormalParameter ||
                param.metadata.isNotEmpty ||
                param.covariantKeyword != null) {
              _reject('Only explicitly typed method parameters supported');
            }
          }
          final element = member.declaredFragment!.element;
          final name = member.name.lexeme;
          memberSymbols[element] = _privateMember(owner.library.ownerUri, name);
          methods[element] = member;
          methodOwners[element] = owner;
          if (!member.isAbstract) {
            final kind = member.isOperator
                ? 'operator'
                : member.isGetter
                ? 'getter'
                : member.isSetter
                ? 'setter'
                : 'method';
            final id = _hash(
              '${owner.library.ownerUri}::$kind::${owner.node.typeName.lexeme}::${_operatorName(member)}',
            );
            final helper = '${entityPrefix}method_$id';
            helpers[element] = helper;
            records[helper] = {
              'library': owner.library.ownerUri,
              'name': '${owner.node.typeName.lexeme}.${_operatorName(member)}',
              'entity': id,
              'kind': '${member.isStatic ? 'static' : 'instance'}-$kind',
              'owner': owner.symbol,
            };
          }
        } else {
          _reject('Unsupported class member');
        }
      }
    }
    // Pre-create bridges for all visible inherited concrete user/SDK methods. A
    // patch can introduce a super call without changing the baseline class.
    for (final owner in declarations.values) {
      final seen = <String>{};
      final superUses = _SuperUses();
      owner.node.accept(superUses);
      final ancestors = <InterfaceElement>[];
      void collect(InterfaceElement element) {
        ancestors.addAll(element.mixins.reversed.map((t) => t.element));
        if (element is MixinElement) {
          ancestors.addAll(
            element.superclassConstraints.reversed.map((t) => t.element),
          );
          for (final constraint in element.superclassConstraints.reversed) {
            collect(constraint.element);
          }
        }
        final parent = element.supertype?.element;
        if (parent != null &&
            (declarations.containsKey(parent) ||
                sdkAncestors.containsKey(parent))) {
          ancestors.add(parent);
          collect(parent);
        }
      }

      collect(owner.element);
      // on-constraints include interface-only members (ListBase implements
      // List). A source super call resolves these against the applying class.
      final constraintInterfaces = <InterfaceElement>{};
      if (owner.element is MixinElement) {
        for (final constraint
            in (owner.element as MixinElement).superclassConstraints) {
          for (final type in constraint.element.allSupertypes) {
            if (!ancestors.contains(type.element) &&
                constraintInterfaces.add(type.element)) {
              ancestors.add(type.element);
            }
          }
        }
      }
      for (final parent in ancestors) {
        final parentOwner = declarations[parent] ?? sdkAncestors[parent];
        if (parentOwner == null) continue;
        for (final method in <ExecutableElement>[
          ...parent.methods,
          ...parent.getters,
          ...parent.setters,
        ]) {
          if (method.isStatic) continue;
          final declaration = methods[method.baseElement];
          final name = memberSymbols[method.baseElement] ?? method.name!;
          if (name.startsWith('_') &&
              parentOwner.library.ownerUri != owner.library.ownerUri)
            continue;
          final dispatchName = declaration?.isOperator == true
              ? _operatorName(declaration!)
              : name;
          final kind = method is GetterElement
              ? 'get'
              : method is SetterElement
              ? 'set'
              : 'call';
          if (constraintInterfaces.contains(parent) &&
              !superUses.selectors.contains('$kind::$dispatchName'))
            continue;
          // An abstract/synthetic nearer member still shadows deeper methods.
          if (!seen.add('$kind::$dispatchName')) continue;
          // Abstract on-constraint members can be supplied by the applying
          // superclass. Emit only source-used abstract super bridges: eager
          // calls would impose new concrete-super requirements on applications.
          if (method.isAbstract &&
              !(owner.element is MixinElement &&
                  superUses.selectors.contains('$kind::$dispatchName')))
            continue;
          if (declaration == null &&
              !fieldOwners.containsKey(method.baseElement))
            continue;
          owner.bridges[method.baseElement] =
              '${entityPrefix}super_${_hash('${owner.symbol}::$dispatchName')}';
        }
      }
      if (owner.bridges.keys.any(
        (element) => methods[element]?.name.lexeme == '[]=',
      )) {
        owner.indexCellBridge =
            '${entityPrefix}super_index_${_hash(owner.symbol)}';
      }
    }
  }

  void prepareInterfaceBridges() {
    // Super helpers become members of Dart's implicit interfaces. An implements
    // clause does not inherit their bodies. Supply exact-signature unreachable
    // helpers without altering any source member (notably noSuchMethod).
    // Source identifiers in our generated namespace are rejected, and method
    // helpers are invoked only by their actual declaring implementation.
    for (final owner in declarations.values) {
      final inherited = <InterfaceElement>{};
      void inherit(InterfaceElement element) {
        if (!inherited.add(element)) return;
        for (final mixin in element.mixins) {
          inherit(mixin.element);
        }
        final parent = element.supertype?.element;
        if (parent != null) inherit(parent);
      }

      for (final mixin in owner.element.mixins) {
        inherit(mixin.element);
      }
      final parent = owner.element.supertype?.element;
      if (parent != null) inherit(parent);
      if (owner.element is MixinElement) {
        for (final constraint
            in (owner.element as MixinElement).superclassConstraints) {
          inherit(constraint.element);
        }
      }
      // CFE permits missing foreign private interface members, synthesizing
      // throwing forwarders even when a class overrides noSuchMethod. Public
      // private-name mangling must not turn them into business obligations.
      if (owner.element is ClassElement &&
          !(owner.element as ClassElement).isAbstract) {
        for (final entry in owner.element.inheritedMembers.entries) {
          final member = entry.value;
          if (!member.isPrivate ||
              member.library == owner.element.library ||
              owner.element.getInheritedConcreteMember(entry.key) != null) {
            continue;
          }
          final symbol = memberSymbols[member.baseElement];
          if (symbol != null)
            owner.privateInterfaceStubs[member.baseElement] = symbol;
        }
      }
      final emitted = <String>{};
      for (final type in owner.element.allSupertypes) {
        final interface = declarations[type.element];
        if (interface == null || inherited.contains(type.element)) continue;
        for (final entry in interface.bridges.entries) {
          final kind = entry.key is GetterElement
              ? 'get'
              : entry.key is SetterElement
              ? 'set'
              : 'call';
          if (emitted.add('$kind::${entry.value}')) {
            owner.bridgeStubs.add(entry);
          }
        }
        if (interface.indexCellBridge != null &&
            emitted.add(interface.indexCellBridge!)) {
          owner.indexCellStubs.add(interface);
        }
      }
    }
  }

  String? superBridge(InterfaceElement owner, Element? target) =>
      declarations[owner]?.bridges[target?.baseElement];

  String lower() {
    final output = StringBuffer();
    final cellLibraries = <String, String>{};
    // An indexed super lvalue stays indexed with exact read/write types.
    // Dart keeps argument checks, ordering, short-circuiting and await semantics.
    String cellClass(_Class owner) =>
        cellLibraries.putIfAbsent(owner.library.ownerUri, () {
          final id = _hash(
            '${owner.library.ownerUri}::infrastructure::super-index-cell',
          );
          final symbol = '${entityPrefix}class_${id}__SuperIndexCell';
          records[symbol] = {
            'library': owner.library.ownerUri,
            'name': '<super-index-cell>',
            'entity': id,
            'kind': 'class',
            'generated': 'super-index-cell',
          };
          final source =
              '''class $symbol<RI, WI, R, W> {
        final R Function(RI) read;
        final void Function(WI, W) write;
        $symbol(this.read, this.write);
        R operator [](RI index) => read(index);
        void operator []=(WI index, W next) { write(index, next); }
      }''';
          manifest[symbol] = {
            'library': owner.library.ownerUri,
            'name': '<super-index-cell>',
            'source': source,
            'source_sha256': _hash(source),
          };
          output.writeln(source);
          return symbol;
        });
    final privateTraps = <Element, String>{};
    // CFE-created noSuchMethod forwarders carry a native Invocation. Using the
    // public Invocation factories loses the VM's original error details.
    String privateInterfaceTrap(
      ExecutableElement member,
    ) => privateTraps.putIfAbsent(member, () {
      final parent = fieldOwners[member] ?? methodOwners[member]!;
      final library = parent.library.ownerUri;
      final kind = member is GetterElement
          ? 'get'
          : member is SetterElement
          ? 'set'
          : 'call';
      final id = _hash(
        '$library::infrastructure::private-interface::${parent.symbol}::$kind::${member.name}',
      );
      final contract = '${entityPrefix}class_${id}__PrivateContract';
      final trap = '${entityPrefix}class_${_hash('$id::trap')}__PrivateTrap';
      final method = methods[member];
      final parameters = method?.parameters?.parameters ?? <FormalParameter>[];
      final positional = parameters
          .where((p) => p.isPositional)
          .map((p) => 'dynamic ${parameterName(p)}')
          .toList();
      final named = parameters
          .where((p) => p.isNamed)
          .map((p) => 'required dynamic ${parameterName(p)}')
          .toList();
      if (method == null && member is SetterElement)
        positional.add('dynamic value');
      final formals = [
        ...positional,
        if (named.isNotEmpty) '{${named.join(', ')}}',
      ].join(', ');
      final arguments = method == null
          ? (member is SetterElement ? 'value' : '')
          : forwardArguments(parameters);
      final types = [
        for (var i = 0; i < member.typeParameters.length; i++)
          '${entityPrefix}failureType$i',
      ];
      final generics = types.isEmpty ? '' : '<${types.join(', ')}>';
      final name = member.name!;
      final declaration = member is GetterElement
          ? 'dynamic get $name;'
          : member is SetterElement
          ? 'set $name($formals);'
          : 'dynamic $name$generics($formals);';
      final invocation = member is GetterElement
          ? '$trap(${entityPrefix}failureReceiver).$name'
          : member is SetterElement
          ? '$trap(${entityPrefix}failureReceiver).$name = $arguments'
          : '$trap(${entityPrefix}failureReceiver).$name$generics($arguments)';
      for (final entry in {
        contract: 'abstract class $contract { $declaration }',
        trap:
            'class $trap implements $contract { '
            'final Object ${entityPrefix}failureReceiver; $trap(this.${entityPrefix}failureReceiver); '
            'static dynamic fail$generics(Object ${entityPrefix}failureReceiver${formals.isEmpty ? '' : ', $formals'}) => $invocation; '
            'dynamic noSuchMethod(msbEntity_sdk_core.Invocation invocation) => '
            'throw msbEntity_sdk_core.NoSuchMethodError.withInvocation(${entityPrefix}failureReceiver, invocation); }',
      }.entries) {
        records[entry.key] = {
          'library': library,
          'name': '<private-interface-$kind-${member.name}>',
          'entity': _hash(entry.key),
          'kind': 'class',
          'generated': 'private-interface-trap',
        };
        manifest[entry.key] = {
          'library': library,
          'name': records[entry.key]!['name'],
          'source': entry.value,
          'source_sha256': _hash(entry.value),
        };
        output.writeln(entry.value);
      }
      return trap;
    });
    for (final owner in declarations.values) {
      final node = owner.node;
      final classParameters = node.typeParameters;
      final classArguments = owner.element.typeParameters
          .map((p) => entities[p]!)
          .toList();
      final receiverType =
          '${owner.symbol}${classArguments.isEmpty ? '' : '<${classArguments.join(', ')}>'}';
      final classBody = StringBuffer();
      final lifted = StringBuffer();
      for (final member in node.body.members) {
        if (member is MethodDeclaration) {
          final element = member.declaredFragment!.element;
          final name = memberSymbols[element]!;
          final returnType = member.returnType == null
              ? typeText(element.returnType)
              : text(owner, member.returnType!);
          final parameters = member.parameters == null
              ? '()'
              : text(owner, member.parameters!);
          final typeParameters = member.typeParameters == null
              ? ''
              : text(owner, member.typeParameters!);
          final helperParameters = <String>[
            if (!member.isStatic)
              ...?classParameters?.typeParameters.map((p) => text(owner, p)),
            ...?member.typeParameters?.typeParameters.map(
              (p) => text(owner, p),
            ),
          ];
          final helperTypeParameters = helperParameters.isEmpty
              ? ''
              : '<${helperParameters.join(', ')}>';
          final helperArguments = [
            if (!member.isStatic) ...classArguments,
            ...?member.typeParameters?.typeParameters.map((p) => p.name.lexeme),
          ];
          final typeArguments = helperArguments.isEmpty
              ? ''
              : '<${helperArguments.join(', ')}>';
          final args = forwardArguments(
            member.parameters?.parameters ?? <FormalParameter>[],
          );
          final signature =
              '${member.isStatic ? 'static ' : ''}' +
              (member.isGetter
                  ? '$returnType get $name'
                  : member.isSetter
                  ? '$returnType set $name$parameters'
                  : '$returnType ${member.isOperator ? 'operator ' : ''}$name$typeParameters$parameters');
          if (member.isAbstract) {
            classBody.writeln('$signature;');
            continue;
          }
          final helper = helpers[element]!;
          final forwarded = member.isStatic
              ? args
              : 'this${args.isEmpty ? '' : ', $args'}';
          final action = returnType == 'void'
              ? '$helper$typeArguments($forwarded);'
              : 'return $helper$typeArguments($forwarded);';
          classBody.writeln('$signature { $action }');
          final ref = visitor(
            owner,
            receiver: member.isStatic ? null : _receiver,
          );
          member.body.accept(ref);
          final body = _rewrite(owner.library.source, member.body, ref.edits);
          records[helper]!['references'] = ref.references.toList()..sort();
          final inner = parameters.substring(1, parameters.length - 1);
          final helperFormals = [
            if (!member.isStatic) '$receiverType $_receiver',
            if (inner.isNotEmpty) inner,
          ].join(', ');
          lifted.writeln(
            '$returnType $helper$helperTypeParameters($helperFormals) $body',
          );
        } else {
          final extra = <_Edit>[];
          if (member is FieldDeclaration && member.fields.type == null) {
            for (final variable in member.fields.variables) {
              final field = owner.element.getField(variable.name.lexeme)!;
              final name = memberSymbols[field]!;
              final declaration = text(
                owner,
                variable,
                extra: [
                  if (name != variable.name.lexeme)
                    _Edit(variable.name.offset, variable.name.end, name),
                ],
              );
              classBody.writeln(
                '${member.isStatic ? 'static ' : ''}${member.fields.lateKeyword != null ? 'late ' : ''}${member.fields.isConst
                    ? 'const '
                    : member.fields.isFinal
                    ? 'final '
                    : ''}${typeText(field.type)} $declaration;',
              );
            }
            continue;
          }
          if (member is FieldDeclaration) {
            for (final variable in member.fields.variables) {
              final name = _privateMember(
                owner.library.ownerUri,
                variable.name.lexeme,
              );
              if (name != variable.name.lexeme)
                extra.add(_Edit(variable.name.offset, variable.name.end, name));
            }
          }
          if (member is ConstructorDeclaration) {
            if (member.typeName != null) {
              // Constructor declaration type names do not always resolve to the
              // ClassElement; handle this declaration token explicitly.
              final refs = visitor(owner);
              member.accept(refs);
              refs.edits.removeWhere(
                (edit) => edit.start == member.typeName!.offset,
              );
              refs.edits.add(
                _Edit(
                  member.typeName!.offset,
                  member.typeName!.end,
                  owner.symbol,
                ),
              );
              if (member.name != null) {
                final name = _privateMember(
                  owner.library.ownerUri,
                  member.name!.lexeme,
                );
                if (name != member.name!.lexeme)
                  refs.edits.add(
                    _Edit(member.name!.offset, member.name!.end, name),
                  );
              }
              classBody.writeln(
                _rewrite(owner.library.source, member, refs.edits),
              );
              continue;
            }
          }
          classBody.writeln(text(owner, member, extra: extra));
        }
      }
      for (final (entry, stub) in [
        for (final entry in owner.bridges.entries) (entry, false),
        for (final entry in owner.bridgeStubs) (entry, true),
        for (final entry in owner.privateInterfaceStubs.entries) (entry, true),
      ]) {
        String implementation(String expression) {
          if (owner.privateInterfaceStubs.containsKey(entry.key)) {
            final trap = privateInterfaceTrap(entry.key as ExecutableElement);
            final declaration = methods[entry.key];
            final typeArguments = forwardTypeArguments(
              declaration?.typeParameters,
            );
            final args = declaration == null
                ? (entry.key is SetterElement ? 'value' : '')
                : forwardArguments(
                    declaration.parameters?.parameters ?? <FormalParameter>[],
                  );
            return '$trap.fail$typeArguments(this${args.isEmpty ? '' : ', $args'})';
          }
          return stub
              ? "throw StateError('Invalid generated super bridge receiver')"
              : expression;
        }

        final fieldOwner = fieldOwners[entry.key];
        if (fieldOwner != null) {
          final element = entry.key as ExecutableElement;
          final names = {...entities, ...superSubstitutions(owner, fieldOwner)};
          final name = memberSymbols[entry.key]!;
          if (element is GetterElement) {
            classBody.writeln(
              '${typeText(element.returnType, names: names)} get ${entry.value} => ${implementation('super.$name')};',
            );
          } else {
            final type = typeText(
              element.formalParameters.single.type,
              names: names,
            );
            classBody.writeln(
              'set ${entry.value}($type value) { ${implementation('super.$name = value')}; }',
            );
          }
          continue;
        }
        final method = methods[entry.key]!;
        final parent = methodOwners[entry.key]!;
        final substitutions = superSubstitutions(owner, parent);
        final returnType = method.returnType == null
            ? typeText(
                method.declaredFragment!.element.returnType,
                names: {...entities, ...substitutions},
              )
            : text(parent, method.returnType!, substitutions: substitutions);
        final parameters = method.parameters == null
            ? '()'
            : text(parent, method.parameters!, substitutions: substitutions);
        final args = forwardArguments(
          method.parameters?.parameters ?? <FormalParameter>[],
        );
        final typeParameters = method.typeParameters == null
            ? ''
            : text(
                parent,
                method.typeParameters!,
                substitutions: substitutions,
              );
        final typeArguments = forwardTypeArguments(method.typeParameters);
        final name = memberSymbols[entry.key];
        if (method.isOperator) {
          final arguments = method.parameters!.parameters
              .map((p) => p.name!.lexeme)
              .toList();
          final expression = switch (_operatorName(method)) {
            'unary-' => '-super',
            '~' => '~super',
            '[]' => 'super[${arguments[0]}]',
            '[]=' => 'super[${arguments[0]}] = ${arguments[1]}',
            _ => 'super $name ${arguments[0]}',
          };
          // Equality accepts a nullable RHS even when the operator parameter
          // itself is non-nullable; retain the native null comparison behavior.
          final bridgeParameters = name == '=='
              ? '(Object? ${arguments[0]})'
              : parameters;
          classBody.writeln(
            '$returnType ${entry.value}$bridgeParameters { ${returnType == 'void' ? '' : 'return '}${implementation(expression)}; }',
          );
        } else if (method.isGetter) {
          classBody.writeln(
            '$returnType get ${entry.value} => ${implementation('super.$name')};',
          );
        } else if (method.isSetter) {
          classBody.writeln(
            '$returnType set ${entry.value}$parameters { ${implementation('super.$name = $args')}; }',
          );
        } else {
          classBody.writeln(
            '$returnType ${entry.value}$typeParameters$parameters { ${returnType == 'void' ? '' : 'return '}${implementation('super.$name$typeArguments($args)')}; }',
          );
        }
      }
      for (final exposed in [
        if (owner.indexCellBridge != null) owner,
        ...owner.indexCellStubs,
      ]) {
        final setter = exposed.bridges.keys.firstWhere(
          (e) => methods[e]?.name.lexeme == '[]=',
        );
        final getters = exposed.bridges.keys.where(
          (e) => methods[e]?.name.lexeme == '[]',
        );
        final getter = getters.isEmpty ? null : getters.first;
        final setOwner = methodOwners[setter]!;
        final setElement = methods[setter]!.declaredFragment!.element;
        final writeType = typeText(
          setElement.formalParameters[1].type,
          names: {...entities, ...superSubstitutions(owner, setOwner)},
        );
        final readType = getter == null
            ? 'Never'
            : typeText(
                methods[getter]!.declaredFragment!.element.returnType,
                names: {
                  ...entities,
                  ...superSubstitutions(owner, methodOwners[getter]!),
                },
              );
        final writeIndexType = typeText(
          setElement.formalParameters[0].type,
          names: {...entities, ...superSubstitutions(owner, setOwner)},
        );
        final readIndexType = getter == null
            ? 'dynamic'
            : typeText(
                methods[getter]!
                    .declaredFragment!
                    .element
                    .formalParameters[0]
                    .type,
                names: {
                  ...entities,
                  ...superSubstitutions(owner, methodOwners[getter]!),
                },
              );
        final read = getter == null
            ? "throw StateError('No super index getter')"
            : '${exposed.bridges[getter]}(index)';
        if (exposed != owner) {
          classBody.writeln(
            '${cellClass(exposed)}<$readIndexType, $writeIndexType, $readType, $writeType> get ${exposed.indexCellBridge} => throw StateError(\'Invalid generated super bridge receiver\');',
          );
          continue;
        }
        classBody.writeln(
          '${cellClass(exposed)}<$readIndexType, $writeIndexType, $readType, $writeType> get ${exposed.indexCellBridge} => '
          '${cellClass(exposed)}<$readIndexType, $writeIndexType, $readType, $writeType>(($readIndexType index) => $read, ($writeIndexType index, $writeType next) { ${exposed.bridges[setter]}(index, next); });',
        );
      }
      // Preserve modifiers and superclass, but replace methods with stable
      // wrappers. Constructor/field/hierarchy changes are checked by the backend.
      final headerRefs = visitor(owner);
      node.extendsClause?.accept(headerRefs);
      node.withClause?.accept(headerRefs);
      node.onClause?.accept(headerRefs);
      node.implementsClause?.accept(headerRefs);
      node.typeParameters?.accept(headerRefs);
      headerRefs.edits.add(
        _Edit(node.typeName.offset, node.typeName.end, owner.symbol),
      );
      headerRefs.edits.add(
        _Edit(node.body.offset, node.body.end, '{\n$classBody}\n'),
      );
      final normalized = _rewrite(owner.library.source, node, headerRefs.edits);
      output.writeln(normalized);
      output.write(lifted);
      manifest[owner.symbol] = {
        'library': owner.library.ownerUri,
        'name': node.typeName.lexeme,
        'source': normalized,
        'source_sha256': _hash(normalized),
      };
    }
    return output.toString();
  }
}

// Track source-level super requirements without visiting inherited SDK bodies.
class _SuperUses extends RecursiveAstVisitor<void> {
  final selectors = <String>{};
  @override
  void visitSuperExpression(SuperExpression node) {
    final parent = node.parent;
    if (parent is MethodInvocation) {
      selectors.add('call::${parent.methodName.name}');
    } else if (parent is PropertyAccess) {
      final name = parent.propertyName;
      if (name.inGetterContext()) {
        selectors.add('get::${name.name}');
        selectors.add('call::${name.name}'); // Method tear-off.
      }
      if (name.inSetterContext()) selectors.add('set::${name.name}');
    } else if (parent is IndexExpression) {
      if (parent.inGetterContext()) selectors.add('call::[]');
      if (parent.inSetterContext()) selectors.add('call::[]=');
    } else if (parent is BinaryExpression) {
      selectors.add(
        'call::${parent.operator.lexeme == '!=' ? '==' : parent.operator.lexeme}',
      );
    } else if (parent is PrefixExpression) {
      selectors.add(
        'call::${parent.operator.lexeme == '-' ? 'unary-' : parent.operator.lexeme}',
      );
    }
  }
}
