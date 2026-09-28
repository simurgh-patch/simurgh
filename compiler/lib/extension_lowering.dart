part of 'source_graph.dart';

// Keep native extension syntax for receiver inference, tear-offs, null-aware
// calls and property assignment ordering. Each resolved selector is made unique
// before combining libraries, so unrelated extensions cannot change resolution.
class _Extensions {
  _Extensions(this.classes);
  final _Classes classes;
  final declarations = <(_Library, ExtensionDeclaration, String)>[];
  final helpers = <ExecutableElement, String>{};
  final storage = <ExtensionElement, String>{};

  void register(_Library library, ExtensionDeclaration node) {
    if (node.augmentKeyword != null || node.onClause == null) {
      _reject('Extension augmentation is not supported');
    }
    final element = node.declaredFragment!.element;
    final name =
        node.name?.lexeme ??
        '<unnamed:${declarations.where((e) => e.$1.ownerUri == library.ownerUri && e.$2.name == null).length}>';
    final id = _hash('${library.ownerUri}::extension::$name');
    final symbol = '${entityPrefix}extension_$id';
    classes.entities[element] = symbol;
    classes.records[symbol] = {
      'library': library.ownerUri,
      'name': name,
      'entity': id,
      'kind': 'extension',
    };
    for (var i = 0; i < element.typeParameters.length; i++) {
      classes.entities[element.typeParameters[i]] =
          '${entityPrefix}type_${_hash('$id::$i')}';
    }
    for (final member in node.body.members) {
      if (member is FieldDeclaration) {
        if (!member.isStatic || member.externalKeyword != null) {
          _reject('Extension fields require native static storage');
        }
        final adapter = storage.putIfAbsent(element, () {
          final storageId = _hash('$id::storage');
          final adapter = '${entityPrefix}class_${storageId}__ExtensionStorage';
          classes.records[adapter] = {
            'library': library.ownerUri,
            'name': '$name.<storage>',
            'entity': storageId,
            'kind': 'class',
            'generated': 'extension-storage',
          };
          return adapter;
        });
        for (final variable in member.fields.variables) {
          final field = variable.declaredFragment!.element as FieldElement;
          final selector =
              '${entityPrefix}extensionField_${_hash('$id::${field.name}')}';
          classes.memberSymbols[field] = selector;
          for (final e in [field.getter, field.setter]) {
            if (e != null) classes.entities[e] = '$adapter.$selector';
          }
        }
        continue;
      }
      if (member is! MethodDeclaration ||
          member.externalKeyword != null ||
          member.isAbstract) {
        _reject('Unsupported extension member: ${member.toSource()}');
      }
      if (member.isOperator)
        _reject('Extension operators require explicit receiver linkage');
      final executable = member.declaredFragment!.element;
      final selector =
          '${entityPrefix}extensionMember_${_hash('$id::${member.name.lexeme}')}';
      classes.memberSymbols[executable] = selector;
      final kind = member.isGetter
          ? 'getter'
          : member.isSetter
          ? 'setter'
          : 'method';
      final helperId = _hash('$id::$kind::${member.name.lexeme}');
      final helper = '${entityPrefix}extensionHelper_$helperId';
      helpers[executable] = helper;
      classes.records[helper] = {
        'library': library.ownerUri,
        'name': '$name.$kind ${member.name.lexeme}',
        'entity': helperId,
        'kind': 'extension-$kind',
        'owner': symbol,
        if (member.body.isAsynchronous)
          'async_return_supported': supportsAsyncReturn(executable.returnType),
      };
    }
    declarations.add((library, node, symbol));
  }

  String lower() {
    final output = StringBuffer();
    for (final (library, node, symbol) in declarations) {
      _References visitor({String? receiver}) => _References(
        classes.entities,
        classes: classes,
        libraryUri: library.ownerUri,
        receiver: receiver,
      );
      String text(AstNode node) {
        final refs = visitor();
        node.accept(refs);
        return _rewrite(library.source, node, refs.edits);
      }

      final element = node.declaredFragment!.element;
      final receiverType = classes.typeText(element.extendedType);
      final generics = node.typeParameters == null
          ? ''
          : text(node.typeParameters!);
      final body = StringBuffer();
      final lifted = StringBuffer();
      final storageBody = StringBuffer();
      for (final member in node.body.members.whereType<FieldDeclaration>()) {
        final modifiers =
            'static ${member.fields.isLate ? 'late ' : ''}${member.fields.isConst
                ? 'const '
                : member.fields.isFinal
                ? 'final '
                : ''}';
        for (final variable in member.fields.variables) {
          final field = variable.declaredFragment!.element as FieldElement;
          final refs = visitor();
          variable.initializer?.accept(refs);
          final initializer = variable.initializer == null
              ? ''
              : ' = ${_rewrite(library.source, variable.initializer!, refs.edits)}';
          storageBody.writeln(
            '${member.metadata.map(text).join('\n')}\n$modifiers${classes.typeText(field.type)} ${classes.memberSymbols[field]}$initializer;',
          );
        }
      }
      if (storageBody.isNotEmpty) {
        output.writeln('class ${storage[element]} {\n$storageBody}');
      }
      for (final member in node.body.members.whereType<MethodDeclaration>()) {
        final executable = member.declaredFragment!.element;
        final selector = classes.memberSymbols[executable]!;
        final helper = helpers[executable]!;
        final result = classes.typeText(executable.returnType);
        final parameters = member.parameters == null
            ? '()'
            : text(member.parameters!);
        final methodGenerics = member.typeParameters == null
            ? ''
            : text(member.typeParameters!);
        final typeParameters = [
          if (!member.isStatic) ...?node.typeParameters?.typeParameters,
          ...?member.typeParameters?.typeParameters,
        ];
        final helperGenerics = typeParameters.isEmpty
            ? ''
            : '<${typeParameters.map(text).join(', ')}>';
        final typeArguments = typeParameters.isEmpty
            ? ''
            : '<${typeParameters.map((p) => classes.entities[p.declaredFragment!.element] ?? p.name.lexeme).join(', ')}>';
        final arguments = forwardArguments(
          member.parameters?.parameters ?? <FormalParameter>[],
        );
        final forwarded =
            '${member.isStatic ? '' : 'this${arguments.isEmpty ? '' : ', '}'}$arguments';
        final signature = member.isGetter
            ? '$result get $selector'
            : member.isSetter
            ? '$result set $selector$parameters'
            : '$result $selector$methodGenerics$parameters';
        final annotations = member.metadata.map(text).join('\n');
        body.writeln(
          '$annotations\n${member.isStatic ? 'static ' : ''}$signature { ${result == 'void' ? '' : 'return '}$helper$typeArguments($forwarded); }',
        );
        final refs = visitor(receiver: member.isStatic ? null : _receiver);
        member.body.accept(refs);
        classes.records[helper]!['references'] = refs.references.toList()
          ..sort();
        final helperParameters = member.isStatic
            ? parameters
            : '($receiverType $_receiver${parameters == '()' ? '' : ', ${parameters.substring(1, parameters.length - 1)}'})';
        lifted.writeln(
          '$annotations\n$result $helper$helperGenerics$helperParameters ${_rewrite(library.source, member.body, refs.edits)}',
        );
      }
      output.writeln(
        '${node.metadata.map(text).join('\n')}\nextension $symbol$generics on $receiverType {\n$body}',
      );
      output.write(lifted);
    }
    return output.toString();
  }
}
