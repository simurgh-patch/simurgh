class Tag<T> {
  final T value;
  const Tag(this.value);
  const Tag.named(this.value);
}

@Tag<int>(7)
enum Flag {
  @Tag<String>('enum-value')
  on,
}

@pragma('vm:never-inline')
@Tag<String>.named('function')
int add(@Tag<int>(3) int value) => value + 1;
@Tag<String>('async')
Future<int> later(int value) async => add(value);
@deprecated
@Tag<String>('global')
var shared = 2, other = 3;
@Tag<String>('alias')
typedef Callback<@Tag<String>('alias-T') T> = T Function(T);

@Tag<Flag>(Flag.on)
class Box<@Tag<String>('class-T') T> {
  @Tag<String>('field')
  final int value;
  @Tag<String>('constructor')
  const Box(@Tag<String>('constructor-param') this.value);
  @Tag<String>('method')
  @pragma('vm:never-inline')
  String label<@Tag<String>('method-U') U>(
    @Tag<String>('method-param') U item,
  ) {
    @Tag<String>('inner-method')
    String inner(@Tag<String>('inner-param') String text) => text;
    return inner('$value:$item');
  }
}

@pragma('vm:prefer-inline')
int fast() => 2;
@pragma('vm:entry-point')
int entry() => 8;
int consume() => fast() + entry();

Future<void> main() async {
  @Tag<String>('local')
  int local(@Tag<String>('local-param') int value) => value * 2;
  @Tag<String>('local-var')
  final number = 3;
  final box = Box<int>(4);
  print(
    '${add(3)}:${await later(4)}:${box.label('x')}:${Flag.on}:${Flag.on.name}:${shared + other}:${local(number)}:${consume()}',
  );
}
