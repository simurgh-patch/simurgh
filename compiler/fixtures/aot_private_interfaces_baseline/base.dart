import 'foreign.dart';
part 'home.dart';

class Base<T> {
  T _field;
  Base(this._field);
  T _method(T value) => value;
  U _collision<U>(U receiver, {String suffix = 'c'}) => receiver;
  int get _property => 9;
  set _property(int next) {}
  U _generic<U extends num>(U _, {String suffix = 'default'}) =>
      throw StateError('base');
}

Object? read(Base value) => value._field;
void write(Base value, Object? x) {
  value._field = x;
}

Object? call(Base value) => value._method(1);
Symbol fieldSymbol() => #_field;

Object? property(Base value) => value._property;
void setProperty(Base value) {
  value._property = 8;
}

Object? generic(Base value) => value._generic<int>(2);

Object? collision(Base value) => value._collision<int>(7);
