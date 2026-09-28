import 'package:flutter/foundation.dart';

bool changed() => listEquals([1], [2]);
void main() {
  final value = ValueNotifier<int>(3);
  value.addListener(() => print('notifier:${value.value}'));
  value.value = 4;
  print('diagnostic:${IntProperty("count", value.value)}');
  print('blend:${changed()}');
  value.dispose();
}
