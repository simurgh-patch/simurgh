class Base<T> {
  T value;
  final T fixed;
  late T deferred;
  late final T once;
  int? optional;
  int _hidden = 5;
  Base(this.value, this.fixed);
}

class PrivateChild extends Base<int> {
  PrivateChild() : super(1, 2);
  int update() => super._hidden += 10;
}
