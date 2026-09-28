import 'dart:ui';

extension type const LayoutInfo._((Size, Offset, Size) _info) {
  Size get childSize => _info.$1;
  Offset get paintOffset => _info.$2;
  Size get overlaySize => _info.$3;
  Offset project() =>
      paintOffset + Offset(childSize.width * 10, overlaySize.height * 10);
}
LayoutInfo make() =>
    const LayoutInfo._((Size(2, 3), Offset(5, 7), Size(11, 13)));
Offset origin() => make().project();
Offset Function() blender() => make().project;
void main() {
  final point = origin();
  final callback = blender();
  print('layout:${point.dx}:${point.dy}');
  print('callback:${callback().dx}:${callback().dy}');
  print(
    'representation:${make() is Record}:${make().childSize.width}:${make().overlaySize.height}',
  );
}
