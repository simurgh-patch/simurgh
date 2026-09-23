import 'dart:collection';

class Concrete<T> extends ListBase<T> {
  final List<T> values;
  Concrete(this.values);
  int get length => values.length;
  set length(int value) => values.length = value;
  T operator [](int index) => values[index];
  void operator []=(int index, T value) => values[index] = value;
}

mixin Choosing<T> on ListBase<T> {
  T pick() => super[1];
}

class Chosen<T> extends Concrete<T> with Choosing<T> {
  Chosen(super.values);
}

List<int> make() => Chosen<int>([3, 4]);
int consume(List<int> list) => list.first;
int pick(List<int> list) => (list as Choosing<int>).pick();
void main() {
  final list = make();
  print('first:${consume(list)}');
  print('picked:${pick(list)}');
}
