class Base<T> {
  final T value;
  final int step;
  const Base(this.value, {this.step = 2});
  const Base.named({required this.value, this.step = 3});
  String read() => '$value:$step:patch';
}

class Defaults {
  final int value;
  const Defaults([this.value = 9]);
}

class Private {
  final int _value;
  const Private(this._value);
  int read() => _value;
}
