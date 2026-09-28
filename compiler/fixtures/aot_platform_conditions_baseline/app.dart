import 'absent.dart' if (dart.library.async) 'present.dart' as p0;
import 'absent.dart' if (dart.library.collection) 'present.dart' as p1;
import 'absent.dart' if (dart.library.concurrent) 'present.dart' as p2;
import 'absent.dart' if (dart.library.convert) 'present.dart' as p3;
import 'absent.dart' if (dart.library.core) 'present.dart' as p4;
import 'absent.dart' if (dart.library.developer) 'present.dart' as p5;
import 'absent.dart' if (dart.library.ffi) 'present.dart' as p6;
import 'absent.dart' if (dart.library.io) 'present.dart' as p7;
import 'absent.dart' if (dart.library.isolate) 'present.dart' as p8;
import 'absent.dart' if (dart.library.math) 'present.dart' as p9;
import 'absent.dart' if (dart.library.typed_data) 'present.dart' as p10;
import 'absent.dart' if (dart.library.cli) 'present.dart' as p11;
import 'absent.dart' if (dart.library.nativewrappers) 'present.dart' as p12;
import 'absent.dart' if (dart.library.vmservice_io) 'present.dart' as p13;
import 'absent.dart' if (dart.library.mirrors) 'present.dart' as p14;
import 'absent.dart' if (dart.library.html) 'present.dart' as p15;
import 'absent.dart' if (dart.library.js) 'present.dart' as p16;
import 'absent.dart' if (dart.library.js_util) 'present.dart' as p17;
import 'absent.dart' if (dart.library.js_interop) 'present.dart' as p18;
import 'absent.dart' if (dart.library.js_interop_unsafe) 'present.dart' as p19;
import 'absent.dart' if (dart.library.ui) 'present.dart' as p20;
import 'barrel.dart' as exported;
import 'absent.dart' if (dart.library.ffi == 'true') 'present.dart' as equal;
import 'absent.dart' if (dart.library.html == '') 'present.dart' as empty;
import 'absent.dart'
    if (dart.library.js_interop == 'false') 'present.dart'
    as falseValue;
import 'absent.dart'
    if (dart.library.io) 'present.dart'
    if (dart.library.ffi) 'absent.dart'
    as first;

void main() {
  print('async:${p0.value()}');
  print('collection:${p1.value()}');
  print('concurrent:${p2.value()}');
  print('convert:${p3.value()}');
  print('core:${p4.value()}');
  print('developer:${p5.value()}');
  print('ffi:${p6.value()}');
  print('io:${p7.value()}');
  print('isolate:${p8.value()}');
  print('math:${p9.value()}');
  print('typed_data:${p10.value()}');
  print('cli:${p11.value()}');
  print('nativewrappers:${p12.value()}');
  print('vmservice_io:${p13.value()}');
  print('mirrors:${p14.value()}');
  print('html:${p15.value()}');
  print('js:${p16.value()}');
  print('js_util:${p17.value()}');
  print('js_interop:${p18.value()}');
  print('js_interop_unsafe:${p19.value()}');
  print('ui:${p20.value()}');
  print(
    'edges:${exported.value()}:${equal.value()}:${empty.value()}:${falseValue.value()}:${first.value()}',
  );
}
