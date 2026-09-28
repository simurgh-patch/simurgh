import 'dart:collection';
import 'dart:async';

@pragma('vm:keep-name')
class Root<T> {
  T stored;
  Root(this.stored);
  T value(T next) => next;
  T get current => stored;
  set current(T next) {
    stored = next;
  }

  R map<R>(R Function(T) convert) => convert(stored);
  String trace() => 'root';
  String _private() => 'private';
}

mixin Services<T> on Root<T> {
  @override
  T value(T next) => super.value(next);
  @override
  T get current => super.current;
  @override
  set current(T next) {
    super.current = next;
  }

  @override
  R map<R>(R Function(T) convert) => super.map<R>(convert);
  @override
  String trace() => '${super.trace()}:services';
  @override
  String _private() => '${super._private()}:services';
}
mixin Painting<T> on Root<T>, Services<T> {
  T exchange(T next) {
    final previous = super.current;
    super.current = super.value(next);
    return previous;
  }

  R project<R>(R Function(T) convert) => super.map<R>(convert);
  String Function() saved() => super.trace;
  @override
  String trace() => '${super.trace()}:patched';
  String hidden() => super._private();
}

class App<T> extends Root<T> with Services<T>, Painting<T> {
  App(super.stored);
}

class ReadOnly<T> extends UnmodifiableListView<T> {
  ReadOnly(super.source);
  String render() => super.join('-');
  T firstValue() => super.first;
}

@pragma('vm:keep-name')
class Label {
  @pragma('vm:keep-name')
  String value() => 'changed';
}

extension Ordered<T extends Comparable<T>> on List<T> {
  T selected() => first.compareTo(last) >= 0 ? first : last;
}

class Asset {
  final bool main;
  Asset({required this.main});
}

Asset asset() => Asset(main: false);
void acceptVoid(void value) {}
Future<void> finish() => Future<void>.value();
Future<void> main() async {
  await finish().then<void>((void value) {
    acceptVoid(value);
    print('void:done');
  });
  print('ordered:${<String>['a', 'b'].selected()}');
  print('selector:${asset().main}');
  final app = App<int>(3);
  print('trace:${app.trace()}:${app.saved()()}');
  print(
    'exchange:${app.exchange(7)}:${app.current}:${app.project<String>((v) => '$v!')}',
  );
  print('private:${app.hidden()}');
  final view = ReadOnly<int>([4, 5]);
  print('view:${view.render()}:${view.firstValue()}');
  try {
    view[0] = 1;
  } on UnsupportedError {
    print('readonly:true');
  }
  print('name:${Label()}:${Label().runtimeType}:${Label().value()}');
}
