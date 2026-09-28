class Box {
  final int value;
  Box(this.value);
}

extension Read on Box {
  int read() => value;
}

extension on int {
  int anonymous() => this + 1;
}

int retained(Box box) => box.read();
void main() {
  print('added:${retained(Box(3))}:${2.anonymous()}');
}
