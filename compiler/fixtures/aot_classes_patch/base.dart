class Base {
  int _value;
  Base(this._value);

  int _adjust(int value) => value * 3;
  int compute(int delta) {
    _value += delta;
    return _adjust(_value);
  }

  int Function(int) callback() {
    return (int delta) {
      _value += delta * 2;
      return _adjust(_value);
    };
  }

  int assignmentForms(int delta) {
    this._value = this._value + delta * 2;
    _value++;
    ++this._value;
    return _adjust(_value);
  }

  Base self() => this;
  void fail() => throw StateError('patched member');
}
