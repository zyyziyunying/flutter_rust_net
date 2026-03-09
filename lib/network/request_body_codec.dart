import 'dart:convert';
import 'dart:typed_data';

import 'net_models.dart';

/// Normalizes request bodies to bytes so Dio and Rust keep the same wire payload.
Uint8List? encodeRequestBody(
  Object? body, {
  List<int>? bodyBytes,
  required NetChannel channel,
}) {
  if (body != null && bodyBytes != null) {
    throw NetException(
      code: NetErrorCode.parse,
      message: 'request body is ambiguous: set either body or bodyBytes',
      channel: channel,
    );
  }

  if (bodyBytes != null) {
    return _encodeRawBodyBytes(bodyBytes, channel: channel);
  }

  if (body == null) {
    return null;
  }
  if (body is ByteBuffer || body is TypedData) {
    throw NetException(
      code: NetErrorCode.parse,
      message:
          'typed-data request bodies must use bodyBytes; use body for JSON arrays',
      channel: channel,
    );
  }
  if (body is String) {
    return Uint8List.fromList(utf8.encode(body));
  }

  try {
    return Uint8List.fromList(utf8.encode(jsonEncode(body)));
  } on JsonUnsupportedObjectError catch (error) {
    final unsupported = error.unsupportedObject;
    final unsupportedType =
        unsupported == null ? body.runtimeType : unsupported.runtimeType;
    throw NetException(
      code: NetErrorCode.parse,
      message:
          'request body contains a non-JSON-encodable value: $unsupportedType',
      channel: channel,
      cause: error,
    );
  }
}

Uint8List _encodeRawBodyBytes(
  List<int> bodyBytes, {
  required NetChannel channel,
}) {
  for (var index = 0; index < bodyBytes.length; index++) {
    final value = bodyBytes[index];
    if (value < 0 || value > 255) {
      throw NetException(
        code: NetErrorCode.parse,
        message: 'bodyBytes[$index] must be in range 0..255, got $value',
        channel: channel,
      );
    }
  }
  return Uint8List.fromList(bodyBytes);
}
