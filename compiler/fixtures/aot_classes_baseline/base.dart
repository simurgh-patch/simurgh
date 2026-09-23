class Base {
  int _value;
  Base(this._value);

  int _adjust(int value) => value * 2;
  int compute(int delta) {
    _value += delta;
    return _adjust(_value);
  }

  int Function(int) callback() {
    return (int delta) {
      _value += delta;
      return _adjust(_value);
    };
  }

  int assignmentForms(int delta) {
    this._value = this._value + delta;
    _value++;
    ++this._value;
    return _adjust(_value);
  }

  Base self() => this;
  void fail() => throw StateError('baseline member');
}
