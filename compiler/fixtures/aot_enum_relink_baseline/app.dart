enum State {
  ready(3),
  running(5);

  const State(this.amount);
  final int amount;
}

class Holder {
  final State value;
  const Holder(this.value);
}

State stored = State.ready;
State make() => State.running;
String typed(State state) => switch (state) {
  State.ready => 'ready',
  State.running => 'running',
};
String read(Enum state) => '${state.name}:${state.index}:$state';
void main() {
  final item = Holder(make());
  print(
    '${read(item.value)}:${item.value.amount}:${typed(item.value)}:${stored.amount}',
  );
  print(State.values.map(read).join('|'));
  var last = '';
  for (int i = 0; i < 100000; i++) {
    last = 'allocation-$i-${i * 17}';
  }
  if (!last.startsWith('allocation-99999-')) throw StateError('GC');
  print('gc:${read(item.value)}');
}
