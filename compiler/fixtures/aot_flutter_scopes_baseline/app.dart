import 'dart:ui' as ui;

class Root {
  ui.Offset get point => const ui.Offset(1, 2);
}

abstract class Interface implements Root {}

mixin Render on Root {
  ui.Offset project() => point.translate(1, 1);
}

class App extends Interface with Render {
  @override
  ui.Offset get point => const ui.Offset(3, 4);
}

ui.Offset shadow(ui.Offset point) {
  final point = const ui.Offset(5, 6);
  return point;
}

Future<ui.Offset> promoted({ui.Offset? point}) async {
  point ??= const ui.Offset(7, 8);
  await Future<void>.value();
  return point.translate(1, 1);
}

Future<void> main() async {
  final render = App().project();
  final local = shadow(ui.Offset.zero);
  final async = await promoted();
  print('render:${render.dx}:${render.dy}');
  print('shadow:${local.dx}:${local.dy}');
  print('async:${async.dx}:${async.dy}');
}
