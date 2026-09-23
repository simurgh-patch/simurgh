import 'dart:convert';

class Rank implements Comparable<Rank> {
  final int value;
  Rank(this.value);
  int compareTo(Rank other) => value.compareTo(other.value);
}

class TextSink implements Sink<String> {
  String output = '';
  bool closed = false;
  void add(String data) {
    output += data;
  }

  void close() {
    closed = true;
  }
}

Comparable<Rank> make() => Rank(5);
Iterator<int> iterator() => [3, 4].iterator;
Exception failure() => FormatException('old');
String ordered() {
  final values = [Rank(2), Rank(1), Rank(3)];
  values.sort();
  return values.map((item) => item.value).join(',');
}

int compare(Comparable<Rank> value) => value.compareTo(Rank(2));
bool rejects(Comparable<Rank> value) {
  try {
    final dynamic erased = value;
    erased.compareTo('wrong');
    return false;
  } catch (error) {
    return error is TypeError;
  }
}

String encoded(TextSink sink) {
  final conversion = JsonEncoder().startChunkedConversion(sink);
  conversion.add([1, 2]);
  conversion.close();
  return '${sink.output}:${sink.closed}';
}

int consume(Iterator<int> value) {
  var total = 0;
  while (value.moveNext()) {
    total += value.current;
  }
  return total;
}

String caught() {
  try {
    throw failure();
  } catch (error) {
    return error.toString();
  }
}

int churn(Comparable<Rank> value, int Function(Rank) callback) {
  var last = '';
  for (int i = 0; i < 100000; i++) {
    last = 'allocation-$i-${i * 17}';
  }
  if (!last.startsWith('allocation-99999-')) throw StateError('GC');
  return compare(value) + callback(Rank(1));
}

void main() {
  final value = make();
  print('sort:${ordered()}');
  print('compare:${compare(value)}');
  print('reject:${rejects(value)}');
  print('sink:${encoded(TextSink())}');
  print('iterator:${consume(iterator())}');
  print('caught:${caught()}');
  print('gc:${churn(value, value.compareTo)}');
}
