import 'package:flutter/foundation.dart';
import 'package:characters/characters.dart';

extension Count on String {
  int get measured => characters.length + 1;
}

int retained() => 'a👨‍👩‍👧‍👦'.measured;
void main() {
  final value = ValueNotifier<int>(retained());
  print('clusters:${value.value}');
  print('unicode:${'a👨‍👩‍👧‍👦'.characters.toList().length}');
  print('blend:${listEquals([value.value], [3])}');
  value.dispose();
}
