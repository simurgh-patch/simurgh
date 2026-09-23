import 'base.dart';
import 'child.dart';

int invoke(Base value) => value.compute(2);
Base make(int value) => Child(value + 1);
String caught(Base value) {
  try {
    value.fail();
    return 'missing exception';
  } catch (error) {
    return error.toString();
  }
}

int churn(int Function(int) callback) {
  var index = 0;
  var last = '';
  while (index < 100000) {
    last = 'allocation-$index-${index * 17}';
    index++;
  }
  if (!last.startsWith('allocation-99999-')) throw StateError('Bad allocation');
  return callback(1);
}

void main() {
  final base = Base(5);
  final child = Child(5);
  print('base=${invoke(base)}');
  print('virtual=${invoke(child)}');
  print('direct=${Child(5).compute(2)}');
  final method = child.compute;
  print('tearoff=${method(1)}');
  final callback = child.callback();
  print('captured=${churn(callback)}');
  print('created=${invoke(make(5))}');
  print('caught=${caught(child)}');
  print('self=${identical(child, child.self())}');
  print('assignments=${Base(5).assignmentForms(1)}');
  print('methodIdentity=${method == child.compute}');
}
