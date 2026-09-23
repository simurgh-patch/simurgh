class Base {
  int _value;
  Base(this._value);
  int get value => _value + 100;
  void set value(int next) { _value = next * 2; }
}
class Child extends Base {
  Child(int value) : super(value);
  int get value => super.value + 1;
  void set value(int next) { super.value = next - 1; }
  int step() { super.value += 2; return super.value++; }
}
int read(Base object) => object.value;
void write(Base object, int value) { object.value = value; }
int churn(Base object) {
  int total = 0;
  int i = 0;
  while (i < 100000) { total += Base(i).value; i++; }
  if (total == 0) throw StateError('allocation failed');
  return object.value;
}
void main() {
  final object = Child(5);
  print('read=${read(object)}');
  write(object, 20);
  print('write=${read(object)}');
  print('step=${object.step()}');
  print('after=${read(object)}');
  print('gc=${churn(object)}');
}
