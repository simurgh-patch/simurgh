class Payload {
  final String value;
  Payload(this.value);
  String toString() => value;
}

class Other {
  String toString() => 'other';
}

class Base {
  Object stored = 'initial';
  void set value(covariant Object item) {
    stored = item;
  }

  Object get value => stored;
  String operator [](covariant Object key) => 'base:$key';
  void operator []=(covariant Object key, covariant Object item) {
    stored = item;
  }

  String read(covariant Object item) => 'base:$item';
}

class Child extends Base {
  void set value(Payload item) {
    super.value = item;
  }

  String operator [](String key) => 'patched:$key';
  void operator []=(String key, Payload item) {
    super[key] = item;
  }

  String read(Payload item) => 'patched:${super.read(item)}';
}

class Holder<T> {
  T value;
  Holder(this.value);
  void update(covariant T item) {
    print('updated:$item');
    value = item;
  }
}

void write(Base receiver, Object value) {
  receiver.value = value;
}

void writeIndex(Base receiver, Object key, Object value) {
  receiver[key] = value;
}

String readIndex(Base receiver, Object key) => receiver[key];
String read(Base receiver, Object value) => receiver.read(value);
int exerciseHeap() {
  var checksum = 0;
  for (int i = 0; i < 250000; i++) {
    final items = List<int>.filled(100, i);
    checksum += items[0];
  }
  return checksum;
}

void main() {
  final Base child = Child();
  final item = Payload('ok');
  write(child, item);
  print('set:${child.value}');
  writeIndex(child, 'key', item);
  print('index:${readIndex(child, 'key')}:${child.value}');
  print(read(child, item));
  try {
    write(child, Other());
  } catch (e) {
    print('setter-error:$e');
  }
  try {
    writeIndex(child, 3, item);
  } catch (e) {
    print('key-error:$e');
  }
  try {
    writeIndex(child, 'key', Other());
  } catch (e) {
    print('value-error:$e');
  }
  try {
    read(child, Other());
  } catch (e) {
    print('read-error:$e');
  }
  final Holder<Object> holder = Holder<Payload>(item);
  print('heap:${exerciseHeap()}');
  holder.update(Payload('new'));
  print('held:${holder.value}');
  try {
    holder.update(Other());
  } catch (e) {
    print('generic-error:$e');
  }
}
