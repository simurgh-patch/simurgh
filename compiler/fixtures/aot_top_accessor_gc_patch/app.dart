int Function(int)? saved;

get producer {
  final payload = <int>[17];
  return (int value) => payload[0] + value;
}

set writer(int Function(int) next) {
  final bias = <int>[10];
  saved = (int value) => next(value) + bias[0];
}

T Function<T>(T) get identity => <T>(T value) => value;

int churn() {
  var sum = 0;
  for (var round = 0; round < 160; round++) {
    final rows = List<List<int>>.generate(2000, (int i) => <int>[i, round]);
    sum += rows[round][0];
  }
  return sum;
}

Future<void> main() async {
  final callback = producer;
  writer = callback;
  final generic = identity;
  print('allocation:${churn()}');
  await Future<void>.value();
  print('captured:${callback(3)}');
  print('saved:${saved!(4)}');
  print('generic:${generic<int>(5)}:${generic<String>('ok')}');
}
