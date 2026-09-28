import 'dart:developer' as dev;

class Base<T> {
  T? value;
  T? get read => value;
  set write(T? other) {
    value = other;
  }

  T? echo(T? other) => other;
  T? Function()? get callback =>
      () => value;
}

class VoidChild extends Base<void> {
  void touch() {
    super.echo(null);
    super.write = null;
    super.callback!();
    print('void:baseline');
  }
}

class DynamicChild extends Base<dynamic> {
  dynamic readBack() => super.echo(3);
}

class CallbackChild extends Base<int Function()?> {
  int readBack() => super.echo(() => 4)!();
}

class RecordChild extends Base<(int, String)?> {
  String readBack() => super.echo((5, 'x'))!.$2;
}

class NullableChild extends Base<int?> {
  int? readBack() => super.echo(null);
}

class Promoted<T> {
  final Object? _value;
  final T? _generic;
  const Promoted(this._value, this._generic);
  int implicit() => _value is String ? _value.length : -1;
  int explicit() => this._value is String ? this._value.length : -1;
  int qualified(Promoted<T> other) =>
      other._value is String ? other._value.length : -1;
  int nested() => _value is String ? (_value).length : -1;
  T generic() {
    if (_generic == null) throw StateError('null');
    return _generic;
  }

  Object nonnull() {
    if (_generic == null) throw StateError('null');
    return _generic;
  }

  int changed() => _value is String ? _value.length + 1 : -1;
}

@pragma('vm:platform-const-if', true)
int get platformValue => 5;
int retainedPlatform() => platformValue;
@pragma('vm:notify-debugger-on-exception')
int worker() => 3;
dev.ServiceExtensionResponse response() =>
    dev.ServiceExtensionResponse.result('{"value":${worker()}}');
int measured() => dev.Timeline.timeSync('value', worker);
Comparator<int> comparison() =>
    (a, b) => a.compareTo(b);
void main() {
  final promoted = Promoted<int>('abc', 7);
  print(
    'promoted:${promoted.implicit()}:${promoted.explicit()}:${promoted.qualified(promoted)}:${promoted.nested()}:${promoted.generic()}:${promoted.nonnull()}:${promoted.changed()}',
  );
  final values = [2, 1]..sort(comparison());
  print('sorted:$values');
  VoidChild().touch();
  print(
    'types:${DynamicChild().readBack()}:${NullableChild().readBack()}:${CallbackChild().readBack()}:${RecordChild().readBack()}',
  );
  print('platform:${retainedPlatform()}');
  print('timeline:${measured()}');
  print('response:${response().result}');
}
