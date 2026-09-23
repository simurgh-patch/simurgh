// @dart=3.0
part of 'legacy.dart';

Stream<String> events() async* {
  yield 'new';
  yield* Stream<String>.fromIterable(Holder<String>('part').values());
}
