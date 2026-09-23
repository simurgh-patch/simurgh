import 'dart:collection';

class BaseView<T> extends MapView<int, T> {
  BaseView(super.map);
  T? read() => super[2];
}
