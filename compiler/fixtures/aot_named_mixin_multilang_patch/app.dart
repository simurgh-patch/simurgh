import 'legacy.dart';
import 'extra.dart';

class Child extends Named<int> {
  Child(super.value, [super.extra]);
  int forwarded(int value) => super.plus(value);
}

Base<int> make() => Added<int>.named(value: 7);
String consume(Base<int> value) =>
    '${value.read()}:${value.extra}:${value.runtimeType}';
void main() {
  print(consume(make()));
  print(consume(hidden()));
  print('forward:${Child(3).forwarded(4)}');
}
