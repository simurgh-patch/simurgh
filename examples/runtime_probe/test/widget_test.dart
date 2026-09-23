import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runtime_probe/main.dart';
import 'package:runtime_probe/probe_model.dart';

void main() {
  testWidgets('official semantic baseline is deterministic', (tester) async {
    expect(semanticProbe(), {
      'direct': 207,
      'virtual': 197,
      'generic': 42,
      'closure': 15,
      'exception': 'probe',
    });
  });

  testWidgets('form rejects empty input and accepts a name', (tester) async {
    if (kReleaseMode) {
      // Integration binding normally leaves the native input channel intact.
      // enterText then uses client -1, accepted only by Flutter Debug builds.
      // Register the test input channel to capture a real client ID in AOT.
      // This tests form behavior, not the platform keyboard implementation.
      tester.testTextInput.register();
      addTearDown(tester.testTextInput.unregister);
    }
    await tester.pumpWidget(const ProbeApp());
    await tester.tap(find.byKey(const ValueKey('form')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(find.text('Required'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('username')), 'Tester');
    // A real device resizes the viewport while its keyboard appears. Wait for
    // that layout before calculating the submit button's tap position.
    await tester.pumpAndSettle();
    expect(find.text('Tester'), findsOneWidget);
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(find.text('Hello, Tester'), findsOneWidget);
  });

  testWidgets('long list scrolls without materializing all rows', (
    tester,
  ) async {
    await tester.pumpWidget(const ProbeApp());
    await tester.tap(find.byKey(const ValueKey('list')));
    await tester.pumpAndSettle();
    expect(find.text('Item 0'), findsOneWidget);
    expect(find.text('Item 999'), findsNothing);
    await tester.drag(
      find.byKey(const ValueKey('long-list')),
      const Offset(0, -640),
    );
    await tester.pumpAndSettle();
    expect(find.text('Item 0'), findsNothing);
  });

  testWidgets('navigation opens and returns from detail', (tester) async {
    await tester.pumpWidget(const ProbeApp());
    await tester.tap(find.byKey(const ValueKey('navigation')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open detail'));
    await tester.pumpAndSettle();
    expect(find.text('Detail'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Open detail'), findsOneWidget);
  });

  testWidgets('finite animation completes', (tester) async {
    await tester.pumpWidget(const ProbeApp());
    await tester.tap(find.byKey(const ValueKey('animation')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Animate'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('async scenario produces deterministic output', (tester) async {
    await tester.pumpWidget(const ProbeApp());
    await tester.tap(find.byKey(const ValueKey('async')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Load'));
    await tester.pumpAndSettle();
    expect(find.text('Loaded 200 items'), findsOneWidget);
  });

  testWidgets('leaving during async work does not update disposed state', (
    tester,
  ) async {
    await tester.pumpWidget(const ProbeApp());
    await tester.tap(find.byKey(const ValueKey('async')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Load'));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
