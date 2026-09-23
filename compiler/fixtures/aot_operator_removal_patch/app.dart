class Base {
  int value = 1;
}

class Child extends Base {
  void change() {
    value = 7;
  }
}

void main() {
  final child = Child();
  child.change();
  print('value:${child.value}');
}
