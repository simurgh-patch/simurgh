class Base {
  int value = 1;
  void operator []=(int index, int next) {
    value = next;
  }
}

class Child extends Base {
  void change() {
    super[0] = 3;
  }
}

void main() {
  final child = Child();
  child.change();
  print('value:${child.value}');
}
