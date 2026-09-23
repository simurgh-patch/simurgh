import 'counter.dart';
import 'left.dart' as left;
import 'right.dart' as right;

class Child extends Counter<int> {
  int plus() => super.instance();
}

Object stableToken() => Counter.token;
String caught() {
  try {
    Counter.fail();
    return 'unexpected';
  } catch (error) {
    return '$error';
  }
}

int churn(int Function(int) callback) {
  var last = '';
  for (int i = 0; i < 100000; i++) {
    last = 'allocation-$i-${i * 17}';
  }
  if (!last.startsWith('allocation-99999-')) throw StateError('GC');
  return callback(1);
}

int fromDefault([int amount = Config.amount]) => amount;
int stableRead() => Counter.count;
int invoke(int Function(int, {int factor}) callback) => callback(2, factor: 3);
Future<void> main() async {
  print('add:${Counter.add(2)}:${stableRead()}');
  print('get:${Counter.current}');
  Counter.current = 5;
  print('set:${stableRead()}');
  print('compound:${++Counter.current}:${stableRead()}');
  print('tearoff:${invoke(Counter.add)}');
  print('tearoffIdentity:${identical(Counter.add, Counter.add)}');
  print('generic:${Counter.echo<int>(4)}:${Counter.echo<String>('s')}');
  print('genericIdentity:${identical(Counter.echo<int>, Counter.echo<int>)}');
  print('async:${await Counter.asyncRead()}');
  print('closure:${Counter.callback(2)(3)}');
  print('instance:${Counter<String>().instance()}');
  print('lazy:${Counter.lazy}:${Counter.lazy}:${Counter.initializations}');
  bool unread = false;
  try {
    print(Counter.once);
  } catch (error) {
    unread = true;
  }
  Counter.once = 9;
  bool twice = false;
  try {
    Counter.once = 10;
  } catch (error) {
    twice = true;
  }
  print('late:$unread:$twice:${Counter.once}');
  Counter.fresh = 17;
  print('fresh:${Counter.fresh}');
  print('config:${Config.amount}:${Config.label}');
  print('defaults:${fromDefault()}:${Settings().amount}');
  print('changing:${Changing.read()}');
  print('private:${left.Twin.read()}:${right.Twin.read()}');
  print('token:${identical(stableToken(), Counter.token)}');
  print('caught:${caught()}');
  print('inherited:${Child().plus()}');
  print('gc:${churn(Counter.callback(2))}');
}
