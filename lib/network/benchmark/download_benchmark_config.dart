import 'download_benchmark_support.dart';

enum DownloadBenchChannel { dio, rhttp }

extension DownloadBenchChannelX on DownloadBenchChannel {
  String get cliName => name;

  static DownloadBenchChannel parse(String raw) {
    final normalized = raw.trim().toLowerCase();
    for (final value in DownloadBenchChannel.values) {
      if (value.cliName == normalized) {
        return value;
      }
    }
    throw ArgumentError.value(raw, 'raw', 'unsupported download bench channel');
  }

  static Set<DownloadBenchChannel> parseList(String raw) {
    final values = raw
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .map(parse)
        .toSet();
    if (values.isEmpty) {
      throw ArgumentError.value(
        raw,
        'raw',
        'must contain at least one channel',
      );
    }
    return values;
  }
}

class DownloadBenchConfig {
  final String baseUrl;
  final int fileBytes;
  final int requests;
  final int warmupRequests;
  final int concurrency;
  final int chunkBytes;
  final int chunkDelayMs;
  final Set<DownloadBenchChannel> channels;
  final bool verbose;

  const DownloadBenchConfig({
    this.baseUrl = '',
    this.fileBytes = 16 * 1024 * 1024,
    this.requests = 3,
    this.warmupRequests = 1,
    this.concurrency = 1,
    this.chunkBytes = 64 * 1024,
    this.chunkDelayMs = 0,
    this.channels = const {
      DownloadBenchChannel.dio,
      DownloadBenchChannel.rhttp,
    },
    this.verbose = true,
  });

  void validate() {
    if (fileBytes <= 0) {
      throw ArgumentError.value(fileBytes, 'fileBytes', 'must be > 0');
    }
    if (requests <= 0) {
      throw ArgumentError.value(requests, 'requests', 'must be > 0');
    }
    if (warmupRequests < 0) {
      throw ArgumentError.value(
        warmupRequests,
        'warmupRequests',
        'must be >= 0',
      );
    }
    if (concurrency <= 0) {
      throw ArgumentError.value(concurrency, 'concurrency', 'must be > 0');
    }
    if (chunkBytes <= 0) {
      throw ArgumentError.value(chunkBytes, 'chunkBytes', 'must be > 0');
    }
    if (chunkDelayMs < 0) {
      throw ArgumentError.value(chunkDelayMs, 'chunkDelayMs', 'must be >= 0');
    }
    if (channels.isEmpty) {
      throw ArgumentError.value(channels, 'channels', 'must not be empty');
    }

    final normalizedBaseUrl = resolveDownloadBenchBaseUrl(baseUrl);
    if (normalizedBaseUrl == null) {
      return;
    }
    final uri = Uri.tryParse(normalizedBaseUrl);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw ArgumentError.value(
        baseUrl,
        'baseUrl',
        'must be an absolute URL, e.g. http://127.0.0.1:18080',
      );
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw ArgumentError.value(
        baseUrl,
        'baseUrl',
        'only http/https supported',
      );
    }
    if (uri.hasQuery || uri.hasFragment) {
      throw ArgumentError.value(
        baseUrl,
        'baseUrl',
        'query and fragment are not allowed',
      );
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'baseUrl': baseUrl,
      'fileBytes': fileBytes,
      'requests': requests,
      'warmupRequests': warmupRequests,
      'concurrency': concurrency,
      'chunkBytes': chunkBytes,
      'chunkDelayMs': chunkDelayMs,
      'channels': channels.map((item) => item.cliName).toList()..sort(),
      'verbose': verbose,
    };
  }
}
