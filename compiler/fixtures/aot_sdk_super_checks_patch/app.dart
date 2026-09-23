import 'dart:collection';

class Child extends MapView<int, String> {
  Child() : super(<int, String>{});
  String trace = '';
  dynamic index() {
    trace += 'i';
    return 0;
  }

  dynamic rhs() {
    trace += 'r';
    return 1;
  }

  void run() {
    super[index()] = rhs();
  }
}

void main() {
  final child = Child();
  try {
    child.run();
  } catch (error) {
    print(
      'error:${error.toString().contains("\u0027int\u0027")}:${error.toString().contains("\u0027String\u0027")}:${child.trace}',
    );
  }
}
