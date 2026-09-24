class Base {
  String read(covariant Object item) => 'base:$item';
  String named({required covariant Object item}) => 'named:$item';
}

class Child extends Base {
  String read(String item) => 'patched:$item';
  String named({required String item}) => 'patched-named:$item';
}

class Holder<T> {
  T value;
  Holder(this.value);
  void setValue(covariant T item) {
    value = item;
  }

  T optional([covariant T? item]) => item ?? value;
}

Base make() => Child();
String call(Base item, Object value) => item.read(value);
String named(Base item, Object value) => item.named(item: value);
void main() {
  final child = make();
  print(call(child, 'x'));
  print(named(child, 'y'));
  try {
    call(child, 3);
  } catch (e) {
    print('call-error:${e is TypeError}');
  }
  try {
    named(child, 3);
  } catch (e) {
    print('named-error:${e is TypeError}');
  }
  final String Function(Object) tear = child.read;
  print(tear('z'));
  try {
    tear(3);
  } catch (e) {
    print('tear-error:${e is TypeError}');
  }
  final Holder<Object> holder = Holder<String>('held');
  holder.setValue('ok');
  print('holder:${holder.value}:${holder.optional()}');
  try {
    holder.setValue(3);
  } catch (e) {
    print('holder-error:${e is TypeError}');
  }
}
