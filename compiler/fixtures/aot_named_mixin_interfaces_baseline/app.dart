import 'foreign.dart';
import 'dart:collection';

class Base<T> {
  final T value;
  final int extra;
  const Base(this.value, [this.extra = 2]);
  const Base.named({required this.value, this.extra = 3});
  const Base._hidden(this.value) : extra = 4;
  T read() => value;
}

mixin Label<T> on Base<T> {
  String label() => '${super.read()}:${extra}';
}
class Named<T> = Base<T> with Label<T>;
class Again<T> = Named<T> with Label<T>;

class Child extends Again<int> {
  Child(super.value);
}

mixin IntList implements List<int> {
  int get length => 1;
  set length(int value) {}
  int operator [](int index) => 5;
  void operator []=(int index, int value) {}
}
class Numbers = ListBase<int> with IntList;
String run() {
  final named = Named<int>.named;
  final hidden = Again<int>._hidden;
  const first = Named<int>(7);
  const second = Named<int>(7);
  return '${Child(8).label()}:${named(value: 9).label()}:${hidden(10).label()}:${identical(first, second)}:${Numbers().join(",")}';
}

mixin MockBody {
  dynamic noSuchMethod(Invocation invocation) => 77;
}
class AliasMock = Object with MockBody implements Child;
mixin Empty {}
class AliasPrivate = Object with Empty implements Foreign<int>;
void main() {
  print(run());
  final Child mock = AliasMock();
  print('mock:${mock.read()}');
  print('private:${access(AliasPrivate())}');
}
