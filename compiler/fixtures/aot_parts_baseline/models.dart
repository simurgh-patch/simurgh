part of parts_demo;

class Base<T> {
  final T _value;
  Base._(this._value);
  factory Base(T value) => Base<T>._(value);
  T _read() => _value;
  T get read => _read();
}

class _Hidden {
  final int _value;
  _Hidden(this._value);
}

class _Token {
  final int value;
  const _Token(this.value);
}

_Token token() => const _Token(1);
