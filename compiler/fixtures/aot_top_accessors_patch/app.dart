import 'counter.dart' as counter;
import 'other.dart' as other;

int retained() => counter.value;

void main() {
  print('initial:${retained()}:${other.value}:${counter.readPrivate()}');
  print('compound:${counter.value += 2}:${other.value += 3}');
  print('retained:${retained()}:${counter.readPrivate()}');
  print('callback:${counter.callback(4)}');
}
