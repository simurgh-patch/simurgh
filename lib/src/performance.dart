import 'dart:math' as math;

import 'common.dart';

const benchmarkScenarios = ['form', 'list', 'navigation', 'animation', 'async'];
const benchmarkVariants = ['official', 'custom_base', 'custom_patch'];
const metricRules = {
  'cold_start_ms': (minimum: 30, limit: 1.10, aggregation: 'p95'),
  'ui_frame_p95_ms': (minimum: 5, limit: 1.10, aggregation: 'max'),
  'raster_frame_p95_ms': (minimum: 5, limit: 1.10, aggregation: 'max'),
  'peak_memory_bytes': (minimum: 5, limit: 1.15, aggregation: 'max'),
};

double percentile95(List<double> values) {
  if (values.isEmpty) throw ToolFailure('Cannot aggregate empty samples');
  final sorted = [...values]..sort();
  return sorted[(sorted.length * 0.95).ceil() - 1];
}

/// Evaluates measured data, not evidence authenticity or overall M2 readiness.
Map<String, dynamic> evaluatePerformance(Map<String, dynamic> report) {
  if (report['schema_version'] != 1 ||
      report['mode'] != 'release' ||
      !['android-arm64', 'ios-arm64'].contains(report['target'])) {
    throw ToolFailure(
      'Requires schema 1, ARM64 device target and release mode',
    );
  }
  for (final key in [
    'device_alias',
    'os_version',
    'benchmark_revision',
    'conditions',
  ]) {
    if (report[key] is! String || (report[key] as String).trim().isEmpty) {
      throw ToolFailure('Missing measurement context: $key');
    }
  }
  final variants = report['variants'];
  if (variants is! Map) throw ToolFailure('Missing variants');
  String? logicalSource;
  for (final name in benchmarkVariants) {
    final variant = variants[name];
    if (variant is! Map) throw ToolFailure('Missing variant: $name');
    for (final key in ['artifact_sha256', 'logical_source_sha256']) {
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch('${variant[key]}')) {
        throw ToolFailure('Invalid $key for $name');
      }
    }
    logicalSource ??= variant['logical_source_sha256'] as String;
    if (variant['logical_source_sha256'] != logicalSource) {
      throw ToolFailure('Variants do not represent the same logical source');
    }
  }
  final results = <Map<String, dynamic>>[];
  for (final scenario in benchmarkScenarios) {
    for (final metric in metricRules.entries) {
      final aggregates = <String, double>{};
      for (final name in benchmarkVariants) {
        final scenarios = (variants[name] as Map)['scenarios'];
        final data = scenarios is Map ? scenarios[scenario] : null;
        final raw = data is Map ? data[metric.key] : null;
        if (raw is! List || raw.length < metric.value.minimum) {
          throw ToolFailure(
            '$name/$scenario/${metric.key} needs ${metric.value.minimum} samples',
          );
        }
        final values = <double>[];
        for (final value in raw) {
          if (value is! num || !value.isFinite || value <= 0) {
            throw ToolFailure(
              '$name/$scenario/${metric.key} contains invalid measurements',
            );
          }
          values.add(value.toDouble());
        }
        aggregates[name] = metric.value.aggregation == 'p95'
            ? percentile95(values)
            : values.reduce(math.max);
      }
      for (final name in benchmarkVariants.skip(1)) {
        final ratio = aggregates[name]! / aggregates['official']!;
        results.add({
          'scenario': scenario,
          'metric': metric.key,
          'variant': name,
          'official': aggregates['official'],
          'candidate': aggregates[name],
          'ratio': ratio,
          'maximum_ratio': metric.value.limit,
          'passed': ratio <= metric.value.limit + 1e-12,
        });
      }
    }
  }
  return {
    'schema_version': 1,
    'target': report['target'],
    'thresholds_passed': results.every((result) => result['passed'] == true),
    'results': results,
    'note':
        'Numerical evaluation only. Device provenance, variance and M2 semantics require separate review.',
  };
}
