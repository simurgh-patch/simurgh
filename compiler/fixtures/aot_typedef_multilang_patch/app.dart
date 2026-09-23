import 'extra.dart';
import 'exports.dart' as old;
import 'same.dart' as other;

typedef Callback = String Function(old.Public<int> value);
String consume(old.Public<int> value) => value.label();
Callback callback() => consume;
old.Public<int> make() => AddedAlias(7);
void main() {
  print('type:${make().runtimeType}');
  final factory = old.Public.new;
  final named = old.Public<int>.named;
  print('${callback()(make())}:${factory(8).label()}:${named(9).label()}');
  print(
    '${other.Public(4).value}:${old.privateIdentity()}:${old.legacyCall()}',
  );
}
