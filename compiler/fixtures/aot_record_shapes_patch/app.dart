typedef Row = (String, int, {String label, bool enabled});
Row stored = ('two', 20, label: 'initial', enabled: true);

class Holder {
  final Row value;
  Holder(this.value);
  String label() => '$value';
}

Row make() => ('three', 30, label: 'made', enabled: false);
String consume(Row value) =>
    '${value.$1}:${value.$2}:${value.label}:${value.enabled}';
Object create() => Holder(make());
String stable(Object value) => value.runtimeType.toString();
void main() {
  print('${consume(stored)}:${consume(make())}:${Holder(make()).label()}');
  print('type:${stable(create())}');
  final holder = Holder(make());
  var last = '';
  for (int i = 0; i < 100000; i++) {
    last = 'allocation-$i-${i * 17}';
  }
  if (!last.startsWith('allocation-99999-')) throw StateError('GC');
  print('gc:${holder.label()}');
}
