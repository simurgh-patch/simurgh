part of other_parts;

class _Hidden {
  final int _value;
  _Hidden(this._value);
}

Object hidden() => _Hidden(9);
int read() => _Hidden(9)._value;
