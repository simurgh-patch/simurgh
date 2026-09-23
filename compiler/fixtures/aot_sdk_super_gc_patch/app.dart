import 'dart:collection';

Map<int, int> makeMap() => FreshMap();
Error makeError() => FreshError();
int total(Iterable<int> values) =>
    values.fold<int>(0, (sum, value) => sum + value);
void main() {
  final map = makeMap();
  final values = map.values;
  final error = makeError();
  try {
    throw error;
  } catch (_) {}
  final trace = error.stackTrace;
  var last = '';
  for (int i = 0; i < 100000; i++) {
    last = 'allocation-$i-${i * 17}';
  }
  if (!last.startsWith('allocation-99999-')) throw StateError('GC');
  print('map:${total(values)}');
  print('stack:${trace != null}:${identical(trace, error.stackTrace)}');
  print('error:$error');
}

class FreshMap extends MapBase<int, int> {
  final Map<int, int> data = {1: 10, 2: 20};
  Iterable<int> get keys => data.keys;
  int? operator [](Object? key) => data[key];
  void operator []=(int key, int value) {
    data[key] = value;
  }

  void clear() {
    data.clear();
  }

  int? remove(Object? key) => data.remove(key);
}

class FreshError extends Error {
  String toString() => 'fresh error';
}
