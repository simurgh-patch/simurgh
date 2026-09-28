class Box {
  final int value;
  Box(this.value);
}

extension Read on Box {
  int get result => value + 1;
  String label() => 'value:$result';
}

String retained(Box box) => box.label();
void main() {
  print('relink:${retained(Box(2))}');
}
