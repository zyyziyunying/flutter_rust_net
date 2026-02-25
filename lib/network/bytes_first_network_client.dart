import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'net_models.dart';
import 'network_gateway.dart';

class NetDecodeMetrics {
  final int materializeBodyMs;
  final int decodeBodyMs;
  final int materializedBytes;
  final int bridgeBytes;

  const NetDecodeMetrics({
    required this.materializeBodyMs,
    required this.decodeBodyMs,
    required this.materializedBytes,
    required this.bridgeBytes,
  });
}

class DecodedNetResponse<T> {
  final NetResponse rawResponse;
  final Uint8List bodyBytes;
  final T decoded;
  final NetDecodeMetrics metrics;

  const DecodedNetResponse({
    required this.rawResponse,
    required this.bodyBytes,
    required this.decoded,
    required this.metrics,
  });
}

abstract class NetBodyDecoder<T> {
  Future<T> decode(Uint8List bodyBytes, {required NetResponse response});
}

class BytesBodyDecoder implements NetBodyDecoder<Uint8List> {
  const BytesBodyDecoder();

  @override
  Future<Uint8List> decode(
    Uint8List bodyBytes, {
    required NetResponse response,
  }) async {
    return bodyBytes;
  }
}

class Utf8BodyDecoder implements NetBodyDecoder<String> {
  const Utf8BodyDecoder({this.allowMalformed = false});

  final bool allowMalformed;

  @override
  Future<String> decode(
    Uint8List bodyBytes, {
    required NetResponse response,
  }) async {
    return utf8.decode(bodyBytes, allowMalformed: allowMalformed);
  }
}

class JsonBodyDecoder implements NetBodyDecoder<Object?> {
  const JsonBodyDecoder({
    this.requireJsonContentType = false,
    this.allowMalformedUtf8 = false,
  });

  final bool requireJsonContentType;
  final bool allowMalformedUtf8;

  @override
  Future<Object?> decode(
    Uint8List bodyBytes, {
    required NetResponse response,
  }) async {
    final contentType = _extractContentType(response.headers);
    if (requireJsonContentType && !_isJsonContentType(contentType)) {
      throw FormatException('non-json content-type: ${contentType ?? '-'}');
    }

    if (allowMalformedUtf8) {
      return jsonDecode(utf8.decode(bodyBytes, allowMalformed: true));
    }

    return jsonDecode(utf8.decode(bodyBytes));
  }
}

class JsonModelDecoder<T> implements NetBodyDecoder<T> {
  final T Function(Object? jsonValue) mapper;
  final JsonBodyDecoder _jsonDecoder;

  JsonModelDecoder(
    this.mapper, {
    bool requireJsonContentType = false,
    bool allowMalformedUtf8 = false,
  }) : _jsonDecoder = JsonBodyDecoder(
         requireJsonContentType: requireJsonContentType,
         allowMalformedUtf8: allowMalformedUtf8,
       );

  @override
  Future<T> decode(Uint8List bodyBytes, {required NetResponse response}) async {
    final jsonValue = await _jsonDecoder.decode(bodyBytes, response: response);
    return mapper(jsonValue);
  }
}

class BytesFirstNetworkClient {
  final NetworkGateway gateway;

  const BytesFirstNetworkClient({required this.gateway});

  Future<NetResponse> requestRaw(
    NetRequest request, {
    NetChannel? forceChannel,
  }) {
    return gateway.request(request, forceChannel: forceChannel);
  }

  Future<NetTransferTaskStartResult> startTransferTask(
    NetTransferTaskRequest request, {
    NetChannel? forceChannel,
  }) {
    return gateway.startTransferTask(request, forceChannel: forceChannel);
  }

  Future<List<NetTransferEvent>> pollTransferEvents({int limit = 64}) {
    return gateway.pollTransferEvents(limit: limit);
  }

  Future<bool> cancelTransferTask(String taskId) {
    return gateway.cancelTransferTask(taskId);
  }

  Future<DecodedNetResponse<T>> requestDecoded<T>(
    NetRequest request, {
    required NetBodyDecoder<T> decoder,
    NetChannel? forceChannel,
  }) async {
    final raw = await gateway.request(request, forceChannel: forceChannel);

    final materializeWatch = Stopwatch()..start();
    final bodyBytes = await _materializeBodyBytes(raw);
    materializeWatch.stop();

    final decodeWatch = Stopwatch()..start();
    final decoded = await decoder.decode(bodyBytes, response: raw);
    decodeWatch.stop();

    return DecodedNetResponse<T>(
      rawResponse: raw,
      bodyBytes: bodyBytes,
      decoded: decoded,
      metrics: NetDecodeMetrics(
        materializeBodyMs: materializeWatch.elapsedMilliseconds,
        decodeBodyMs: decodeWatch.elapsedMilliseconds,
        materializedBytes: bodyBytes.length,
        bridgeBytes: raw.bridgeBytes,
      ),
    );
  }

  Future<DecodedNetResponse<Object?>> requestJsonObject(
    NetRequest request, {
    NetChannel? forceChannel,
    bool requireJsonContentType = false,
    bool allowMalformedUtf8 = false,
  }) {
    return requestDecoded<Object?>(
      request,
      forceChannel: forceChannel,
      decoder: JsonBodyDecoder(
        requireJsonContentType: requireJsonContentType,
        allowMalformedUtf8: allowMalformedUtf8,
      ),
    );
  }

  Future<DecodedNetResponse<T>> requestJsonModel<T>(
    NetRequest request, {
    required T Function(Object? jsonValue) mapper,
    NetChannel? forceChannel,
    bool requireJsonContentType = false,
    bool allowMalformedUtf8 = false,
  }) {
    return requestDecoded<T>(
      request,
      forceChannel: forceChannel,
      decoder: JsonModelDecoder<T>(
        mapper,
        requireJsonContentType: requireJsonContentType,
        allowMalformedUtf8: allowMalformedUtf8,
      ),
    );
  }

  Future<Uint8List> _materializeBodyBytes(NetResponse response) async {
    final inline = response.bodyBytes;
    if (inline != null) {
      if (inline is Uint8List) {
        return inline;
      }
      return Uint8List.fromList(inline);
    }

    final filePath = response.bodyFilePath;
    if (filePath == null || filePath.isEmpty) {
      return Uint8List(0);
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
      // best effort: materialization success should not be blocked by cleanup
    }
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
