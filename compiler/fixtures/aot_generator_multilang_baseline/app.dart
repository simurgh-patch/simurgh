// @dart=3.12
import 'legacy.dart';

Iterable<int> make() sync* {
  yield* values(2);
}

Future<void> main() async {
  print('${make().toList()}:${values(2).toList()}:${await events().toList()}');
}
