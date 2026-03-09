import 'dart:convert';
import 'dart:typed_data';

import 'net_models.dart';

/// Normalizes request bodies to bytes so Dio and Rust keep the same wire payload.
Uint8List? encodeRequestBody(
  Object? body, {
  required NetChannel channel,
}) {
  if (body == null) {
    return null;
  }
  if (body is Uint8List) {
    return body;
  }
  if (body is List<int>) {
    return Uint8List.fromList(body);
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
