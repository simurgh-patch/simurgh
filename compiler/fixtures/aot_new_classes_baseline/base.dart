class Base {
  int value;
  Base(this.value);
  int compute(int delta) => value + delta;
  String label() => 'base';
}
