// @dart=3.0
class Base<T> {
  final T value;
  final int extra;
  const Base(this.value, [this.extra = 2]);
  const Base.named({required this.value, this.extra = 3});
  const Base._hidden(this.value) : extra = 4;
  T read() => value;
}

mixin Label<T> on Base<T> {
  String label() => '${super.read()}:${extra}';
  int plus(int _) => _ + extra;
}
class Named<T> = Base<T> with Label<T>;
Base<int> hidden() => Named<int>._hidden(10);
