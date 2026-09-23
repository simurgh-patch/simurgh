part of 'app.dart';

class Added extends Base<int> {
  Added(int value) : super._(value);
  int get read => _value + 100;
}
