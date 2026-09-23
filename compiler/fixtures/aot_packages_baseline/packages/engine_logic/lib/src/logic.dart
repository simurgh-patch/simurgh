import 'package:utility/utility.dart' as util;
int _secret() => 1;
int compute(int n) => util.adjust(n) + _secret();
class Box {
  final int value;
  Box(this.value);
  int read() => value + _secret();
}
String message() => 'package';
