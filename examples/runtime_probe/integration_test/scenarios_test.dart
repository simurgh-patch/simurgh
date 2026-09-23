import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:integration_test/integration_test.dart';

import '../test/widget_test.dart' as scenarios;

// Run the existing semantic and interaction assertions inside a real app
// process. Host widget tests remain available as a faster, separate check.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Release builds have no VM service. Keep a test-only completion marker so
  // the emulator's native log can report the same assertions in AOT mode.
  binding.allTestsPassed.future.then((passed) {
    debugPrint(
      'SIMURGH_INTEGRATION_RESULT '
      '${jsonEncode({'passed': passed, 'tests': binding.results.length})}',
    );
  });
  scenarios.main();
}
