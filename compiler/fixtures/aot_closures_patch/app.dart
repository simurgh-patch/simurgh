int unchanged(int value) => value;
int apply(int Function(int) callback, int value) => callback(value);
int Function(int) makeCounter(int seed) {
  var count = seed;
  int increment(int delta) {
    count += delta * 2;
    return unchanged(count);
  }

  return (int delta) => increment(delta);
}

int Function(int) makeFailure() {
  return (int value) => throw StateError('patched callback');
}

String catchCallback(int Function(int) callback) {
  try {
    callback(0);
    return 'missing exception';
  } catch (error) {
    return error.toString();
  }
}

int churn(int Function(int) callback) {
  var index = 0;
  var last = '';
  while (index < 100000) {
    last = 'allocation-$index-${index * 17}';
    index++;
  }
  if (!last.startsWith('allocation-99999-')) throw StateError('Bad allocation');
  return apply(callback, 1);
}

void main() {
  final counter = makeCounter(10);
  print('closure=${apply(counter, 2)}');
  print('capture=${apply(counter, 3)}');
  print('gc=${churn(counter)}');
  print('exception=${catchCallback(makeFailure())}');
}
