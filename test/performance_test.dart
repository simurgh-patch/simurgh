import 'package:simurgh_cli/src/common.dart';
import 'package:simurgh_cli/src/performance.dart';
import 'package:test/test.dart';

// Synthetic unit-test data. Never recorded as device performance evidence.
Map<String, dynamic> synthetic() => {
  'schema_version': 1,
  'mode': 'release',
  'target': 'ios-arm64',
  'device_alias': 'synthetic-only',
  'os_version': 'synthetic',
  'benchmark_revision': 'synthetic',
  'conditions': 'synthetic unit test, not measured',
  'variants': {
    for (final variant in benchmarkVariants)
      variant: {
        'artifact_sha256': 'a' * 64,
        'logical_source_sha256': 'b' * 64,
        'scenarios': {
          for (final scenario in benchmarkScenarios)
            scenario: {
              for (final metric in metricRules.entries)
                metric.key: List<Object?>.filled(metric.value.minimum, 100.0),
            },
        },
      },
  },
};

void main() {
  test('nearest rank P95 is deterministic', () {
    expect(percentile95(List.generate(30, (i) => (i + 1).toDouble())), 29);
  });
  test('evaluates all variants, scenarios and metrics', () {
    final result = evaluatePerformance(synthetic());
    expect(result['thresholds_passed'], isTrue);
    expect(result['results'], hasLength(40));
  });
  test('rejects missing variant and insufficient launch samples', () {
    final report = synthetic();
    final variants = report['variants'] as Map;
    (variants['custom_patch']['scenarios']['list'] as Map)['cold_start_ms'] = [
      100,
    ];
    expect(() => evaluatePerformance(report), throwsA(isA<ToolFailure>()));
    variants.remove('custom_patch');
    expect(() => evaluatePerformance(report), throwsA(isA<ToolFailure>()));
  });
  test('does not hide a slow frame run in the average', () {
    final report = synthetic();
    report['variants']['custom_patch']['scenarios']['list']['ui_frame_p95_ms'] =
        [100, 100, 100, 100, 120];
    expect(evaluatePerformance(report)['thresholds_passed'], isFalse);
  });
  test('memory threshold is 15 percent, not 10', () {
    final report = synthetic();
    report['variants']['custom_base']['scenarios']['form']['peak_memory_bytes'] =
        List.filled(5, 115);
    expect(evaluatePerformance(report)['thresholds_passed'], isTrue);
    report['variants']['custom_base']['scenarios']['form']['peak_memory_bytes'] =
        List.filled(5, 116);
    expect(evaluatePerformance(report)['thresholds_passed'], isFalse);
  });
  test('rejects fake modes, invalid values and incomparable logical source', () {
    for (final bad in [0, -1, double.nan, double.infinity, '100']) {
      final report = synthetic();
      report['variants']['official']['scenarios']['form']['cold_start_ms'][0] =
          bad;
      expect(() => evaluatePerformance(report), throwsA(isA<ToolFailure>()));
    }
    final report = synthetic()..['mode'] = 'profile';
    expect(() => evaluatePerformance(report), throwsA(isA<ToolFailure>()));
    report['mode'] = 'release';
    report['variants']['custom_patch']['logical_source_sha256'] = 'c' * 64;
    expect(() => evaluatePerformance(report), throwsA(isA<ToolFailure>()));
  });
}
