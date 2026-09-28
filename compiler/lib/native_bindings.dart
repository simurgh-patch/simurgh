part of 'source_graph.dart';

bool _ffiAnnotation(Annotation annotation, String name) {
  final type = annotation.elementAnnotation?.computeConstantValue()?.type;
  return type is InterfaceType &&
      type.element.name == name &&
      type.element.library.uri.toString() == 'dart:ffi';
}

class _NativeBindings {
  _NativeBindings(this.classes, this.defaultAssets);
  final _Classes classes;
  final Map<String, String> defaultAssets;
  final annotations = <Annotation, String>{};
  final contracts = <String, String>{};
  final defaults = <String, String>{};
  final owners = <String>{};
  final bridges = <String, String>{};
  String bridge(
    String library,
    String result,
    String parameterType,
    String expression, {
    String? formals,
  }) {
    final parameters =
        formals ?? (parameterType.isEmpty ? '' : '$parameterType target');
    final shape = '$result ($parameters) => $expression';
    final id = _hash('$library::ffi-bridge::$shape');
    final name = '${entityPrefix}native_$id';
    final source = '$result $name($parameters) => $expression;';
    bridges[name] = source;
    contracts[name] = source;
    classes.records[name] = {
      'library': library,
      'name': '<native-bridge>',
      'entity': id,
      'kind': 'native-bridge',
    };
    return name;
  }

  bool nativeClass(InterfaceElement element) =>
      [element, ...element.allSupertypes.map((t) => t.element)].any(
        (e) =>
            e.library.uri.toString() == 'dart:ffi' &&
            {'Struct', 'Union', 'Opaque'}.contains(e.name),
      );

  void register(
    _Library library,
    CompilationUnitMember? owner,
    AnnotatedNode declaration,
    String name,
    ExecutableElement element,
    String key,
  ) {
    final found = declaration.metadata
        .where((a) => _ffiAnnotation(a, 'Native'))
        .toList();
    if (found.length != 1 ||
        !element.isStatic ||
        element.typeParameters.isNotEmpty) {
      _reject(
        'External declarations require one static dart:ffi Native binding',
      );
    }
    final annotation = found.single;
    final value = annotation.elementAnnotation!.computeConstantValue()!;
    final type = value.type as InterfaceType;
    final symbol = value.getField('symbol')?.toStringValue() ?? name;
    var asset = value.getField('assetId')?.toStringValue();
    if (asset == null) {
      for (final metadata in element.library.metadata.annotations) {
        final constant = metadata.computeConstantValue();
        final annotationType = constant?.type;
        if (annotationType is InterfaceType &&
            annotationType.element.name == 'DefaultAsset' &&
            annotationType.element.library.uri.toString() == 'dart:ffi') {
          asset = constant!.getField('id')!.toStringValue();
        }
      }
    }
    if (asset == null) {
      asset = defaultAssets[key] ?? element.library.uri.toString();
      defaults[key] = asset;
    }
    final text =
        '@${sdkPrefix('dart:ffi')}.Native<${classes.typeText(type.typeArguments.single)}>('
        'symbol: ${jsonEncode(symbol)}, assetId: ${jsonEncode(asset)}, '
        'isLeaf: ${value.getField('isLeaf')!.toBoolValue()})';
    annotations[annotation] = text;
    contracts[key] = text;
    if (owner != null) owners.add(classes.entities[owner.typeElement]!);
  }
}
