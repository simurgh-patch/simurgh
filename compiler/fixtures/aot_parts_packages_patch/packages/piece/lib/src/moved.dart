part of pieces;

class _Box implements View {
  final int _value;
  _Box(this._value);
  int read() => _value + 10;
}

int _old(int _) => _ + 3;
