// @dart=3.12
import 'legacy.dart';
import 'extra.dart';

int make() => extra();
void main() {
  print('${make()}:${read()}');
}
