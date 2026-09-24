import 'default_impl.dart' if (dart.library.io) 'vm_impl.dart' as impl;
import 'barrel.dart' as barrel;

void main() {
  print('result:${impl.value()}:${barrel.label()}');
}
