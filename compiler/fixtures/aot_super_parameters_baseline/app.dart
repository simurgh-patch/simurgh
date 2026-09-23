import 'base.dart';
import 'dart:math' show pi;

class Child<T> extends Base<T> {
  const Child(super.value, {super.step});
  const Child.named({required super.value, super.step}) : super.named();
}

class Grand extends Child<String> {
  const Grand(super.value, {super.step});
}

class BodyChild extends Base<int> {
  final int own;
  BodyChild(super.value) : own = value + 1, super(step: 8);
}

class OverrideDefault extends Base<int> {
  const OverrideDefault(super.value, {super.step = 11});
}

class ForwardDefault extends Defaults {
  const ForwardDefault([super.value]);
}

class PrivateChild extends Private {
  final int local;
  PrivateChild(super._value) : local = _value + 1;
}

Base<int> make() => Child<int>(7);
String invoke(Base<int> value) => value.read();
void main() {
  print('positional:${Child<int>(1).read()}');
  print('explicit:${Child<int>(1, step: 5).read()}');
  print('named:${Child<String>.named(value: 'v').read()}');
  print('namedExplicit:${Child<String>.named(value: 'v', step: 6).read()}');
  print('grand:${Grand('deep').read()}');
  print('default:${ForwardDefault().value}');
  print('body:${BodyChild(4).read()}:${BodyChild(4).own}');
  print('override:${OverrideDefault(3).read()}');
  print('sdk:$pi');
  print(r'raw:$value');
  print('private:${PrivateChild(10).read()}:${PrivateChild(10).local}');
  print('const:${identical(const Child<int>(1), const Child<int>(1))}');
  print('type:${Grand('t') is Base<String>}');
  print('added:${invoke(make())}');
}
