// @dart=3.12
import 'app.dart' as base;
class Added extends base.Box {
  Added(int value) : super(value);
  @override
  int read() => super.read() + 10;
}
