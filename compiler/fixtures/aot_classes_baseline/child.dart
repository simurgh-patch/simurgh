import 'base.dart';

class Child extends Base {
  Child(int value) : super(value);

  int _adjust(int value) => value + 1000;

  @override
  int compute(int delta) => super.compute(delta) + 10;
}
