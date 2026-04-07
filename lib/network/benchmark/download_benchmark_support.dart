import 'dart:math';
import 'dart:io';
import 'dart:typed_data';

Uint8List buildDeterministicDownloadPayload(int bytes) {
  final safeBytes = bytes < 0 ? 0 : bytes;
  final data = Uint8List(safeBytes);
  for (var i = 0; i < safeBytes; i += 1) {
    data[i] = _deterministicDownloadByte(i);
  }
  return data;
}

int expectedDownloadChecksum(int bytes) {
  final safeBytes = bytes < 0 ? 0 : bytes;
  var checksum = 0;
  for (var i = 0; i < safeBytes; i += 1) {
    checksum = ((checksum * 33) + _deterministicDownloadByte(i)) & 0x7fffffff;
  }
  return checksum;
}

Stream<List<int>> streamDeterministicDownloadPayload(
  int bytes, {
  required int chunkBytes,
}) async* {
  final safeBytes = bytes < 0 ? 0 : bytes;
  final safeChunkBytes = chunkBytes <= 0 ? 1 : chunkBytes;
  for (var offset = 0; offset < safeBytes; offset += safeChunkBytes) {
    final length = min(safeChunkBytes, safeBytes - offset);
    final chunk = Uint8List(length);
    for (var i = 0; i < length; i += 1) {
      chunk[i] = _deterministicDownloadByte(offset + i);
    }
    yield chunk;
  }
}

Future<int> rollingDownloadChecksumForFile(File file) async {
  var checksum = 0;
  await for (final chunk in file.openRead()) {
    checksum = rollingDownloadChecksum(chunk, seed: checksum);
  }
  return checksum;
}

int rollingDownloadChecksum(List<int> bytes, {int seed = 0}) {
  var checksum = seed;
  for (final byte in bytes) {
    checksum = ((checksum * 33) + byte) & 0x7fffffff;
  }
  return checksum;
}

Uri buildDownloadBenchUri(
  String baseUrl, {
  required int fileBytes,
  required int chunkBytes,
  required int chunkDelayMs,
}) {
  final resolvedBaseUrl = resolveDownloadBenchBaseUrl(baseUrl);
  if (resolvedBaseUrl == null) {
    throw ArgumentError.value(baseUrl, 'baseUrl', 'must not be empty');
  }
  return Uri.parse('$resolvedBaseUrl/bench/download-file').replace(
    queryParameters: <String, String>{
      'bytes': '$fileBytes',
      'chunkBytes': '$chunkBytes',
      'chunkDelayMs': '$chunkDelayMs',
    },
  );
}

String? resolveDownloadBenchBaseUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  var normalized = trimmed;
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

int _deterministicDownloadByte(int index) {
  return (index * 31 + 17) % 251;
}
