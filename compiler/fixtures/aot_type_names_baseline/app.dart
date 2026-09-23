import 'left.dart' as left;
import 'right.dart' as right;

class Box<T> {
  T value;
  Box(this.value);
  int revision() => 1;
}

class _Local {
  int value = 1;
}

class Layout {
  int value = 1;
}

Object added() => Box<int>(1);
String describe(Object value) => '${value.runtimeType}|$value';
void main() {
  final box = Box<int>(3);
  print('box:${describe(box)}');
  print('nested:${Box<Box<int>>(box).runtimeType}');
  print('local:${describe(_Local())}');
  print('left:${describe(left.hidden())}');
  print('right:${describe(right.hidden())}');
  print(
    'privateDifferent:${left.hidden().runtimeType != right.hidden().runtimeType}',
  );
  print('publicNames:${left.same().runtimeType}|${right.same().runtimeType}');
  print(
    'publicDifferent:${left.same().runtimeType != right.same().runtimeType}',
  );
  print('sameType:${box.runtimeType == Box<int>}');
  print('differentType:${box.runtimeType != Box<String>}');
  print('isBox:${box is Box<int>}');
  print('layout:${describe(Layout())}');
  print('added:${describe(added())}');
  print('revision:${box.revision()}');
  print('sdk:${42.runtimeType}|${'x'.runtimeType}');
}
