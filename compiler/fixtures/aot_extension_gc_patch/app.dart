extension Work on List<int> {
  int call({int add = 1}) => first * 10 + add;
  Future<int> later() async {
    await Future<void>.value();
    return first * 10 + 2;
  }

  Iterable<int> sequence() sync* {
    yield first * 10 + 3;
  }

  Stream<int> stream() async* {
    yield first * 10 + 4;
  }
}

int churn() {
  var sum = 0;
  for (var round = 0; round < 160; round++) {
    final rows = List<List<int>>.generate(2000, (int i) => <int>[i, round]);
    sum += rows[round][0];
  }
  return sum;
}

Future<void> main() async {
  final values = <int>[7];
  final callback = values.call;
  final asyncCallback = values.later;
  print('allocation:${churn()}');
  await Future<void>.value();
  print('captured:${callback(add: 3)}');
  print('later:${await asyncCallback()}');
  print('sequence:${values.sequence().toList()}');
  print('stream:${await values.stream().toList()}');
}
