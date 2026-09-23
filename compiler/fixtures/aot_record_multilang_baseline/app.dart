import 'legacy.dart';

Data make() => (4, value: Box(5));
String consume(Data data) =>
    '${data.$1}:${data.value.read()}:${data.value.runtimeType}';
void main() {
  print(consume(make()));
  print('legacy:${legacy(make())}');
}
