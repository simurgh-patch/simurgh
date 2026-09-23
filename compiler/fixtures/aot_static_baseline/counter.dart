class Counter<T> {
  static var count = 1;
  static final token = Object();
  static int _adjust(int value) => value + _private;
  static int fail() => throw StateError('static-baseline');
  static int _private = 2;
  static int initializations = 0;
  static final lazy = initialize();
  static late final int once;
  static late final int fresh;
  static int initialize() {
    initializations++;
    return 10;
  }

  static int add(int delta, {int factor = 1}) {
    count += delta * factor;
    return _adjust(count);
  }

  static int get current => count;
  static set current(int value) {
    count = value;
  }

  static T echo<T>(T value) => value;
  static Future<int> asyncRead() async => current;
  static int Function(int) callback(int offset) =>
      (int value) => add(value + offset);
  int instance() => add(1);
}

class Config {
  static const amount = 3;
  static final label = 'v$amount';
}

class Settings {
  final int amount;
  const Settings([this.amount = Config.amount]);
}

class Changing {
  static var value = 2;
  static int read() => value;
}
