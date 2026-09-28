import 'dart:ui' as ui;
import 'package:flutter/src/services/message_codec.dart';

class Root<T> {
  final T stored;
  Root(this.stored);
  T get value => stored;
}

mixin Services<T> on Root<T> {
  @override
  T get value => super.value;
}
mixin Painting on Root<ui.Offset>, Services<ui.Offset> {
  ui.Offset project() => super.value.translate(1, 2);
}

class App extends Root<ui.Offset> with Services<ui.Offset>, Painting {
  App(super.stored);
}

ui.Offset origin() => App(const ui.Offset(2, 3)).project();
ui.Offset Function() blender() => origin;
void main() {
  final point = blender()();
  final call = MethodCall('paint', point);
  print('point:${point.dx}:${point.dy}');
  print('codec:${call.runtimeType}:${call.method}');
}
