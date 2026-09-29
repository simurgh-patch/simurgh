class Box {
  final int value;
  const Box.named(this.value);
  @override
  String toString() => 'box:$value';
}

Object make() => const Box.named(2);
void main() {
  print(make());
}
