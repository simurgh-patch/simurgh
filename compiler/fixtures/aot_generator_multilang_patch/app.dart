// @dart=3.12
import 'legacy.dart';
import 'extra.dart';

Iterable<int> make() sync* {
  yield* values(2);
  yield* extra();
}

Future<void> main() async {
  print('${make().toList()}:${values(2).toList()}:${await events().toList()}');
}
