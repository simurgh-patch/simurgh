abstract class AbstractBase {
  abstract covariant var value;
}

class Mock extends AbstractBase {
  dynamic noSuchMethod(Invocation call) => call.isGetter ? 'from-nsm' : null;
}

class Base<T> {
  covariant T value;
  covariant late T later;
  Base(this.value) {
    later = value;
  }
}

class Child extends Base<Object> {
  String value = 'child';
  Child() : super('parent');
  String label() => '${super.value}:$value:${super.later}';
}

class Inferred {
  covariant var value = Object();
}

class Narrow extends Inferred {
  String value = 'narrow';
  String label() => value;
}

void write(Base<Object> item, Object value) {
  item.value = value;
}

void inferredWrite(Inferred item, Object value) {
  item.value = value;
}

void main() {
  final AbstractBase mock = Mock();
  print('abstract:${mock.value}');
  mock.value = 3;
  final child = Child();
  write(child, 'ok');
  print('fields:${child.label()}');
  try {
    write(child, 3);
  } catch (e) {
    print('child-error:$e');
  }
  final Base<Object> generic = Base<String>('generic');
  write(generic, 'next');
  print('generic:${generic.value}:${generic.later}');
  try {
    write(generic, 3);
  } catch (e) {
    print('generic-error:$e');
  }
  try {
    generic.later = 3;
  } catch (e) {
    print('late-error:$e');
  }
  final narrow = Narrow();
  inferredWrite(narrow, 'ok');
  print('inferred:${narrow.label()}');
  try {
    inferredWrite(narrow, 3);
  } catch (e) {
    print('inferred-error:$e');
  }
}
