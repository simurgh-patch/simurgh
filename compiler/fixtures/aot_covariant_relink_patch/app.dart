class FieldOnly {
  covariant Object value = 'field';
}

final FieldOnly field = FieldOnly();

class Base {
  String read(covariant Object value) => 'base:$value';
}

class Child extends Base {
  String read(String value) => 'child:$value';
}

class Added extends Base {
  String read(String value) => 'added:$value';
}

final Base shared = Child();
Base make() => Added();
String invoke(Base item, Object value) => item.read(value);
String describe(Object item) => item.toString();
Future<void> main() async {
  print(field.value);
  print(invoke(make(), 'x'));
  print(invoke(shared, 'y'));
  try {
    print(invoke(make(), 3));
  } catch (e) {
    print('error:$e');
  }
  print(describe(make()));
}
