mixin Display on Enum {
  String toString() => 'changed:$index';
}

enum Mixed with Display { one, two }

enum Custom {
  first._build(3),
  _second._build(7);

  const Custom._build(this.value);
  final int value;
  String get name => 'user-name';
  String toString() => 'updated:${super.toString()}:$value';
  static Custom pick() => _second;
}

String read(Enum item) => '${item.name}:$item';
void main() {
  print('${read(Mixed.one)}:${read(Custom.first)}:${read(Custom.pick())}');
  print(
    '${Custom.values.byName('_second') == Custom.pick()}:${Custom.first.name}:${EnumName(Custom.first).name}',
  );
}
