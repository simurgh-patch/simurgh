abstract interface class Value<T> {
  T get value;
  set value(T value);
  T choose(T other);
  int measure(int delta);
}

abstract class Label {
  String get label;
}

abstract interface class Combined<T> implements Value<T>, Label {}

abstract interface class Growing {
  int read();
  int get extra;
}
