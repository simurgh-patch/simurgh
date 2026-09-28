extension type const Remote._(int _value) implements int {
  const Remote.named(int value) : this._(value);
  int measure() => _value + 2;
}
