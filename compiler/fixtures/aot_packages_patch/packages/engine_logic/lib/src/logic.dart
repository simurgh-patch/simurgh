import 'package:utility/utility.dart' as util;
import 'package:addon/addon.dart' as addon;
int _secret() => 2;
int compute(int n) => util.adjust(n) + _secret();
class Box {
  final int value;
  Box(this.value);
  int read() => value + _secret() + 10;
}
String message() => addon.decorate('package');
