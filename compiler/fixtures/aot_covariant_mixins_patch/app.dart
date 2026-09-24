import 'dart:collection';

class Tag {
  final String value;
  const Tag(this.value);
}

class Base {
  String read(covariant Object item) => 'base:$item';
}

mixin Mixed on Base {
  String read(covariant Object item) => 'mixed:${super.read(item)}';
}

class Child extends Base with Mixed {
  String read(@Tag('input') String item) => 'patched:${super.read(item)}';
}

abstract class Contract {
  String read(covariant Object item);
}

class Mock implements Contract {
  String read(covariant String item);
  dynamic noSuchMethod(Invocation call) =>
      'mock:${call.positionalArguments.first}';
}

class CheckedList extends ListBase<Object> {
  final List<String> values = <String>['old'];
  int get length => values.length;
  set length(int value) {
    values.length = value;
  }

  Object operator [](int index) => values[index];
  void operator []=(int index, covariant String value) {
    values[index] = 'patched:$value';
  }

  String label() => super.join('|');
}

abstract class Formats {
  String record(covariant (Object, Object) value);
  int callback(covariant Function value);
}

class NarrowFormats implements Formats {
  String record((String, int) value) => '${value.$1}:${value.$2}';
  int callback(int Function(int) value) => value(12);
}

String call(Base receiver, Object value) => receiver.read(value);
void main() {
  print(call(Child(), 'x'));
  try {
    call(Child(), 3);
  } catch (e) {
    print('mixed-error:$e');
  }
  final Contract mock = Mock();
  print(mock.read('ok'));
  try {
    mock.read(3);
  } catch (e) {
    print('mock-error:$e');
  }
  final list = CheckedList();
  final List<Object> broad = list;
  broad[0] = 'new';
  print('sdk:${list.label()}');
  try {
    broad[0] = 3;
  } catch (e) {
    print('sdk-error:$e');
  }
  final Formats formats = NarrowFormats();
  print(
    'record:${formats.record(('x', 2))}:${formats.callback((int n) => n + 1)}',
  );
  try {
    formats.record((3, 2));
  } catch (e) {
    print('record-error:$e');
  }
  try {
    formats.callback((String s) => s);
  } catch (e) {
    print('callback-error:$e');
  }
}
