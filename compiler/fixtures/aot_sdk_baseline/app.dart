import 'dart:async' as tasks;
import 'dart:collection' show Queue;
import 'dart:convert' as codec;
import 'dart:math' as math;
import 'dart:typed_data' as bytes;

bytes.Uint8List shared = bytes.Uint8List.fromList([1, 2]);
bytes.Uint8List data(int n) => bytes.Uint8List.fromList([n, 1]);
int stableRead(bytes.Uint8List data) => data[0] + data[1];
List<String> words(String text) => codec.LineSplitter.split(text).toList();
Map<String, dynamic> parsed(String text) => codec.jsonDecode(text) as Map<String, dynamic>;
String encoded() => codec.jsonEncode({'value': 1});
num largest(num a, num b) => math.max(a, b) + 1;
int queued() {
  final queue = Queue<int>.of([1, 2]);
  queue.add(1);
  return queue.fold<int>(0, (sum, n) => sum + n);
}
int sum<T extends Iterable<int>>(T values) => values.fold<int>(1, (sum, n) => sum + n);
Future<int> delayed(int n) async {
  final result = tasks.Completer<int>();
  tasks.scheduleMicrotask(() { result.complete(n + 1); });
  return result.future;
}
tasks.Stream<int> stream() => tasks.Stream<int>.fromIterable([1, 1]);
DateTime stamp() => DateTime.utc(2026, 9, 1);
void mutate() { shared[1] = 1; }
Future<void> main() async {
  print('sdkException=${sdkFailure()}');
  print('firstUse=${firstUse()}');
  print('bytes=${stableRead(data(3))}');
  mutate();
  print('shared=${stableRead(shared)}');
  print('words=${words('one\ntwo').join(':')}');
  print('json=${parsed(encoded())['value']}');
  print('math=${largest(3, 4)}');
  print('queue=${queued()}');
  print('iterable=${sum<List<int>>([2, 3])}');
  print('future=${await delayed(2)}');
  print('stream=${await stream().fold<int>(0, (sum, n) => sum + n)}');
  print('date=${stamp().day}');
}

String firstUse() => 'baseline';

dynamic parseInvalid() => codec.jsonDecode('1');
bool sdkFailure() {
  try { parseInvalid(); return false; } on FormatException { return true; }
}
