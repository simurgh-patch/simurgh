// @dart=3.12
import 'legacy.dart';
import 'extra.dart';

Base make() => Added();
String invoke(Base item, Object value) => item.read(value);
void main() {
  print(invoke(make(), 'x'));
  try {
    invoke(make(), 3);
  } catch (e) {
    print('error:$e');
  }
}
