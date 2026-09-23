import 'base.dart';

Base make(int value) => Base(value);
int invoke(Base value) => value.compute(2);
int readField(Base value) => value.value;
void writeField(Base object, int value) {
  object.value = value;
}

bool checkType(Base value) => value is Base;
bool exactType(Base value) => value.runtimeType == Base;

int churn(Base object) {
  var index = 0;
  var last = '';
  while (index < 100000) {
    last = 'allocation-$index-${index * 17}';
    index++;
  }
  if (!last.startsWith('allocation-99999-')) throw StateError('Bad allocation');
  return object.compute(2);
}

void main() {
  final object = make(5);
  print('virtual=${invoke(object)}');
  print('field=${readField(object)}');
  print('label=${object.label()}');
  final method = object.compute;
  print('tearoff=${method(3)}');
  print('type=${checkType(object)}');
  print('exact=${exactType(object)}');
  print('gc=${churn(object)}');
  print('nested=${invoke(make(-5))}');
  writeField(object, 20);
  print('write=${invoke(object)}');
}
