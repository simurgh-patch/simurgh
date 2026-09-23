// @dart=3.12
import 'legacy.dart';

Enum make() => previous();
String read(Enum value) =>
    '${value.name}:${value.index}:$value:${value.runtimeType}';
void main() {
  print(read(make()));
  print(read(previous()));
}
