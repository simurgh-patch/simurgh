import 'dart:collection';
import 'base.dart';

class Direct<T> extends BaseView<T> {
  Direct(super.map);
}

class Implemented<T> extends MapBase<int, T> implements BaseView<T> {
  final Map<int, T> data;
  Implemented(this.data);
  Iterable<int> get keys => data.keys;
  T? operator [](Object? key) => data[key];
  void operator []=(int key, T value) {
    data[key] = value;
  }

  void clear() {
    data.clear();
  }

  T? remove(Object? key) => data.remove(key);
  T? read() => data[1];
}

class Mock implements BaseView<String> {
  dynamic noSuchMethod(Invocation invocation) => 'mock';
}

String? consume(BaseView<String> value) => value.read();
void update(BaseView<String> value) {
  value[1] = 'written';
}

void main() {
  final direct = Direct<String>({1: 'one', 2: 'two'});
  final implemented = Implemented<String>({1: 'own'});
  print('direct:${consume(direct)}');
  print('implemented:${consume(implemented)}');
  update(implemented);
  print('updated:${consume(implemented)}');
  print('mock:${consume(Mock())}');
  print('identity:${implemented.noSuchMethod == implemented.noSuchMethod}');
}
