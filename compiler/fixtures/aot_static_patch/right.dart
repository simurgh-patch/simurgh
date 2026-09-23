class Twin {
  static int _value = 8;
  static int _read() => _value;
  static int read() => _read();
}
