// @dart=3.12
import 'legacy.dart';
import 'extra.dart';

Enum make() => next();
String read(Enum value) =>
    '${value.name}:${value.index}:$value:${value.runtimeType}';
void main() {
  print(read(make()));
  print(read(previous()));
}
