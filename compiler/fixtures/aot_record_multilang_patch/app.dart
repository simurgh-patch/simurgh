import 'extra.dart';
import 'legacy.dart';

Data make() => (14, value: Added(15));
String consume(Data data) =>
    '${data.$1}:${data.value.read()}:${data.value.runtimeType}';
void main() {
  print(consume(make()));
  print('legacy:${legacy(make())}');
}
