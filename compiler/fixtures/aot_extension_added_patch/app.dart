class Box {
  final int value;
  final int extra;
  Box(this.value) : extra = 5;
}

extension Read on Box {
  int read() => value + extra;
  int get doubled => read() * 2;
}

extension Fresh on String {
  String get label => '$this!';
}

extension on int {
  int anonymous() => this + 1;
}

int retained(Box box) => box.read();
void main() {
  print(
    'added:${retained(Box(3))}:${2.anonymous()}:${Box(2).doubled}:${"ok".label}',
  );
}
