import 'dart:convert';
import 'dart:io';

import '../net_models.dart';
import 'benchmark_types.dart';

class ConsumeMetrics {
  final bool attempted;
  final bool succeeded;
  final int totalMs;
  final int materializeBodyMs;
  final int utf8DecodeMs;
  final int jsonDecodeMs;
  final int modelBuildMs;
  final int bodyBytes;
  final String? skippedReason;

  const ConsumeMetrics({
    required this.attempted,
    required this.succeeded,
    required this.totalMs,
    required this.materializeBodyMs,
    required this.utf8DecodeMs,
    required this.jsonDecodeMs,
    required this.modelBuildMs,
    required this.bodyBytes,
  }) : skippedReason = null;

  const ConsumeMetrics.notAttempted()
    : attempted = false,
      succeeded = false,
      totalMs = 0,
      materializeBodyMs = 0,
      utf8DecodeMs = 0,
      jsonDecodeMs = 0,
      modelBuildMs = 0,
      bodyBytes = 0,
      skippedReason = null;

  const ConsumeMetrics.skipped({
    required String reason,
    this.totalMs = 0,
    this.materializeBodyMs = 0,
    this.bodyBytes = 0,
  }) : attempted = true,
       succeeded = false,
       utf8DecodeMs = 0,
       jsonDecodeMs = 0,
       modelBuildMs = 0,
       skippedReason = reason;
}

Future<ConsumeMetrics> consumeResponse({
  required BenchmarkConfig config,
  required NetResponse response,
}) async {
  if (config.consumeMode == BenchmarkConsumeMode.none) {
    return const ConsumeMetrics.notAttempted();
  }

  final contentType = _extractContentType(response.headers);
  if (!_isJsonContentType(contentType)) {
    return const ConsumeMetrics.skipped(reason: 'non_json_content_type');
  }

  final totalWatch = Stopwatch()..start();
  final materializeWatch = Stopwatch()..start();
  final bodyBytes = await _materializeBodyBytes(response);
  materializeWatch.stop();

  if (bodyBytes.isEmpty) {
    totalWatch.stop();
    return ConsumeMetrics.skipped(
      reason: 'empty_body',
      totalMs: totalWatch.elapsedMilliseconds,
      materializeBodyMs: materializeWatch.elapsedMilliseconds,
      bodyBytes: bodyBytes.length,
    );
  }

  final utf8Watch = Stopwatch()..start();
  final decoded = utf8.decode(bodyBytes);
  utf8Watch.stop();

  final jsonWatch = Stopwatch()..start();
  final jsonValue = jsonDecode(decoded);
  jsonWatch.stop();

  var modelBuildMs = 0;
  if (config.consumeMode == BenchmarkConsumeMode.jsonModel) {
    final modelWatch = Stopwatch()..start();
    final rebuilt = _rebuildJsonObjectGraph(jsonValue);
    if (rebuilt is Map || rebuilt is List) {}
    modelWatch.stop();
    modelBuildMs = modelWatch.elapsedMilliseconds;
  } else {
    if (jsonValue is Map || jsonValue is List) {}
  }

  totalWatch.stop();
  return ConsumeMetrics(
    attempted: true,
    succeeded: true,
    totalMs: totalWatch.elapsedMilliseconds,
    materializeBodyMs: materializeWatch.elapsedMilliseconds,
    utf8DecodeMs: utf8Watch.elapsedMilliseconds,
    jsonDecodeMs: jsonWatch.elapsedMilliseconds,
    modelBuildMs: modelBuildMs,
    bodyBytes: bodyBytes.length,
  );
}

Future<List<int>> _materializeBodyBytes(NetResponse response) async {
  final inline = response.bodyBytes;
  if (inline != null) {
    return inline;
  }
  final filePath = response.bodyFilePath;
  if (filePath == null || filePath.isEmpty) {
    return const <int>[];
  }
  final file = File(filePath);
  try {
    return await file.readAsBytes();
  } finally {
    await _deleteMaterializedFileQuietly(file);
  }
}

Future<void> _deleteMaterializedFileQuietly(File file) async {
  try {
    if (await file.exists()) {
      await file.delete();
    }
  } on FileSystemException {
    // best effort cleanup only
  }
}

String? _extractContentType(Map<String, String> headers) {
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == HttpHeaders.contentTypeHeader) {
      return entry.value.toLowerCase();
    }
  }
  return null;
}

bool _isJsonContentType(String? contentType) {
  if (contentType == null || contentType.isEmpty) {
    return true;
  }
  return contentType.contains('/json') || contentType.contains('+json');
}

Object? _rebuildJsonObjectGraph(Object? node) {
  if (node is Map) {
    final copied = <String, Object?>{};
    node.forEach((key, value) {
      copied[key.toString()] = _rebuildJsonObjectGraph(value);
    });
    return copied;
  }
  if (node is List) {
    return node.map<Object?>(_rebuildJsonObjectGraph).toList(growable: false);
  }
  return node;
}
