import 'dart:collection';

final class Parent {
  final int value;
  Parent(this.value);
  int read() => value;
}

typedef ParentAlias = Parent;

final class Child extends ParentAlias {
  Child(super.value);
  int twice() => read() * 2;
}

typedef Children = Child;
typedef IntList = ListBase<int>;

class Numbers extends IntList {
  int get length => 1;
  set length(int value) {}
  int operator [](int index) => 8;
  void operator []=(int index, int value) {}
}

Parent make() => Children(4);
int consume(Parent value) => value.read();
void main() => print('${consume(make())}:${Numbers().join(",")}');
