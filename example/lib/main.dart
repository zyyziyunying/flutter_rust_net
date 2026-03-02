import 'dart:convert';

import 'package:common/log_upload.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rust_net/network/benchmark/network_benchmark_harness.dart';

void main() {
  runApp(const BenchmarkExampleApp());
}

class BenchmarkExampleApp extends StatelessWidget {
  const BenchmarkExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_rust_net example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const BenchmarkHomePage(),
    );
  }
}

class BenchmarkHomePage extends StatefulWidget {
  const BenchmarkHomePage({super.key});

  @override
  State<BenchmarkHomePage> createState() => _BenchmarkHomePageState();
}

class _BenchmarkHomePageState extends State<BenchmarkHomePage> {
  static const String _defaultUploadUrl = 'http://47.110.52.208:7777/upload';
  static const String _loginPath = '/user/login';
  static const String _loginUsername = 'ziyunying';
  static const String _loginPassword = '123456';
  static const List<_RunPreset> _presets = [
    _RunPreset(
      label: 'Dio smoke (small_json)',
      config: BenchmarkConfig(
        scenario: BenchmarkScenario.smallJson,
        requests: 60,
        warmupRequests: 6,
        concurrency: 6,
        channels: {BenchmarkChannel.dio},
        initializeRust: false,
        verbose: true,
      ),
    ),
    _RunPreset(
      label: 'Dio vs Rust (small_json)',
      config: BenchmarkConfig(
        scenario: BenchmarkScenario.smallJson,
        requests: 120,
        warmupRequests: 12,
        concurrency: 12,
        channels: {BenchmarkChannel.dio, BenchmarkChannel.rust},
        initializeRust: true,
        rustMaxInFlightTasks: 32,
        verbose: true,
      ),
    ),
    _RunPreset(
      label: 'Dio vs Rust (jitter c16 mif32)',
      config: BenchmarkConfig(
        scenario: BenchmarkScenario.jitterLatency,
        requests: 240,
        warmupRequests: 24,
        concurrency: 16,
        channels: {BenchmarkChannel.dio, BenchmarkChannel.rust},
        initializeRust: true,
        rustMaxInFlightTasks: 32,
        verbose: true,
      ),
    ),
  ];

  late _RunPreset _selectedPreset;
  late final TextEditingController _uploadUrlController;
  late final TextEditingController _uploadFieldController;
  late final Dio _uploadDio;
  late final LogUploadClient _logUploadClient;
  bool _running = false;
  bool _uploading = false;
  bool _requireRust = false;
  String _logText =
      'Tap "Run local benchmark". The benchmark spins up a local loopback '
      'server automatically.';
  BenchmarkReport? _lastReport;

  @override
  void initState() {
    super.initState();
    _selectedPreset = _presets.first;
    _uploadUrlController = TextEditingController(text: _defaultUploadUrl);
    _uploadFieldController = TextEditingController(text: 'file');
    _uploadDio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        responseType: ResponseType.plain,
        validateStatus: (status) => status != null,
      ),
    );
    _logUploadClient = LogUploadClient(
      uploader: DioLogUploader(dio: _uploadDio),
      defaults: const LogUploadDefaults(
        timeout: Duration(seconds: 30),
        fields: <String, String>{'source': 'flutter_rust_net_example'},
      ),
    );
  }

  @override
  void dispose() {
    _uploadUrlController.dispose();
    _uploadFieldController.dispose();
    _uploadDio.close(force: true);
    super.dispose();
  }

  Future<void> _runPreset() async {
    if (_running) {
      return;
    }

    void appendLog(String message) {
      _appendLog(message);
    }

    setState(() {
      _running = true;
      _lastReport = null;
      _logText = '[example] starting ${_selectedPreset.label}';
    });

    try {
      final config = _selectedPreset.config.copyWith(requireRust: _requireRust);
      _appendLog('[example] requireRust=$_requireRust');
      final report = await runNetworkBenchmark(config, log: appendLog);
      _appendLog('');
      _appendLog(report.toPrettyText());
      final compareSummary = _buildCompareSummary(report);
      if (compareSummary != null) {
        _appendLog(compareSummary);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _lastReport = report;
      });
    } catch (error) {
      _appendLog('[example] failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
        });
      }
    }
  }

  Future<void> _uploadLastReport() async {
    if (_running || _uploading || _lastReport == null) {
      return;
    }
    final uploadUrlText = _uploadUrlController.text.trim();
    final fieldName = _uploadFieldController.text.trim();
    if (uploadUrlText.isEmpty || fieldName.isEmpty) {
      _appendLog('[example][upload] upload url / field name cannot be empty.');
      return;
    }

    Uri uploadUri;
    try {
      uploadUri = Uri.parse(uploadUrlText);
      if (!uploadUri.hasScheme || !uploadUri.hasAuthority) {
        throw const FormatException('invalid upload url');
      }
    } catch (_) {
      _appendLog('[example][upload] invalid upload url: $uploadUrlText');
      return;
    }

    final report = _lastReport!;
    final fileName = _buildUploadFileName(report);
    final reportJson = const JsonEncoder.withIndent(
      '  ',
    ).convert(report.toJson());

    setState(() {
      _uploading = true;
    });

    _appendLog('[example][upload] uploading $fileName -> $uploadUri');
    try {
      final token = await _loginToken(dio: _uploadDio, uploadUri: uploadUri);
      if (token == null) {
        _appendLog('[example][upload] skipped upload because login failed.');
        return;
      }
      final result = await _logUploadClient.upload(
        uploadUri: uploadUri,
        fileContent: reportJson,
        token: token,
        fileName: fileName,
        fieldName: fieldName,
        fields: <String, String>{
          'scenario': report.config.scenario.cliName,
          'startedAt': report.startedAt.toIso8601String(),
        },
      );
      final detail = _logUploadClient.formatResultDetail(result);
      if (result.success) {
        _appendLog(
          '[example][upload] success '
          'scenario=${report.config.scenario.cliName}, '
          '$detail',
        );
      } else {
        _appendLog(
          '[example][upload] failed '
          'scenario=${report.config.scenario.cliName}, '
          '$detail',
        );
      }
    } catch (error) {
      _appendLog('[example][upload] failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
        });
      }
    }
  }

  Future<String?> _loginToken({
    required Dio dio,
    required Uri uploadUri,
  }) async {
    final loginUri = _loginUriFromUpload(uploadUri);
    _appendLog('[example][upload] login -> $loginUri');

    try {
      final response = await dio.postUri(
        loginUri,
        data: const {'username': _loginUsername, 'password': _loginPassword},
      );
      final statusCode = response.statusCode ?? 0;
      final responseText = _truncate(response.data.toLogUploadResponseBody());
      if (statusCode < 200 || statusCode >= 300) {
        _appendLog(
          '[example][upload] login failed($statusCode), response=$responseText',
        );
        return null;
      }

      final token = _extractToken(response.data);
      if (token == null || token.isEmpty) {
        _appendLog(
          '[example][upload] login success but token missing, response=$responseText',
        );
        return null;
      }
      _appendLog('[example][upload] login success, token received.');
      return token;
    } catch (error) {
      _appendLog('[example][upload] login error: $error');
      return null;
    }
  }

  Uri _loginUriFromUpload(Uri uploadUri) {
    final uri = Uri(
      scheme: uploadUri.scheme,
      host: uploadUri.host,
      port: uploadUri.hasPort ? uploadUri.port : null,
      path: _loginPath,
    );
    return uri;
  }

  String? _extractToken(Object? data) {
    final payload = _normalizePayload(data);
    if (payload is! Map) {
      return null;
    }
    return _extractTokenFromMap(payload);
  }

  Object? _normalizePayload(Object? raw) {
    if (raw is String) {
      try {
        return jsonDecode(raw);
      } catch (_) {
        return raw;
      }
    }
    return raw;
  }

  String? _extractTokenFromMap(Map payload) {
    String? pickByKey(String key) {
      final value = payload[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
      return null;
    }

    const keys = ['token', 'accessToken', 'access_token', 'jwt', 'bearerToken'];
    for (final key in keys) {
      final value = pickByKey(key);
      if (value != null) {
        return value;
      }
    }

    final nestedCandidates = [
      payload['data'],
      payload['result'],
      payload['payload'],
    ];
    for (final candidate in nestedCandidates) {
      if (candidate is Map) {
        final token = _extractTokenFromMap(candidate);
        if (token != null && token.isNotEmpty) {
          return token;
        }
      }
      if (candidate is String && candidate.trim().isNotEmpty) {
        return candidate.trim();
      }
    }
    return null;
  }

  String _buildUploadFileName(BenchmarkReport report) {
    final utc = report.finishedAt.toUtc().toIso8601String();
    final safeUtc = utc.replaceAll(':', '').replaceAll('.', '');
    return 'bench_${report.config.scenario.cliName}_$safeUtc.json';
  }

  String _truncate(String text, {int maxLength = 180}) {
    if (text.length <= maxLength) {
      return text;
    }
    return '${text.substring(0, maxLength)}...';
  }

  void _appendLog(String message) {
    debugPrint(message);
    if (!mounted) {
      return;
    }
    setState(() {
      if (_logText.isEmpty) {
        _logText = message;
      } else {
        _logText = '$_logText\n$message';
      }
    });
  }

  String? _buildCompareSummary(BenchmarkReport report) {
    ChannelBenchmarkResult? dio;
    ChannelBenchmarkResult? rust;

    for (final item in report.channelResults) {
      if (item.channel == BenchmarkChannel.dio.cliName) {
        dio = item;
      } else if (item.channel == BenchmarkChannel.rust.cliName) {
        rust = item;
      }
    }
    if (dio == null || rust == null) {
      return null;
    }

    final reqP95Delta = _deltaPercent(
      base: dio.requestLatencyMs.p95Ms.toDouble(),
      candidate: rust.requestLatencyMs.p95Ms.toDouble(),
    );
    final e2eP95Delta = _deltaPercent(
      base: dio.endToEndLatencyMs.p95Ms.toDouble(),
      candidate: rust.endToEndLatencyMs.p95Ms.toDouble(),
    );
    final throughputDelta = _deltaPercent(
      base: dio.throughputRps,
      candidate: rust.throughputRps,
    );

    return '[example][compare] reqP95 ${_formatDelta(reqP95Delta, lowerIsBetter: true)}, '
        'e2eP95 ${_formatDelta(e2eP95Delta, lowerIsBetter: true)}, '
        'throughput ${_formatDelta(throughputDelta, lowerIsBetter: false)}';
  }

  double _deltaPercent({required double base, required double candidate}) {
    if (base == 0) {
      return 0;
    }
    return ((candidate - base) / base) * 100;
  }

  String _formatDelta(double delta, {required bool lowerIsBetter}) {
    final improved = lowerIsBetter ? delta <= 0 : delta >= 0;
    final trend = improved ? 'better' : 'worse';
    final sign = delta > 0 ? '+' : '';
    return '$sign${delta.toStringAsFixed(1)}% ($trend)';
  }

  @override
  Widget build(BuildContext context) {
    final report = _lastReport;

    return Scaffold(
      appBar: AppBar(title: const Text('flutter_rust_net local benchmark')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Preset',
                  border: OutlineInputBorder(),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<_RunPreset>(
                    isExpanded: true,
                    value: _selectedPreset,
                    items: _presets
                        .map(
                          (preset) => DropdownMenuItem<_RunPreset>(
                            value: preset,
                            child: Text(preset.label),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: _running
                        ? null
                        : (value) {
                            if (value == null) {
                              return;
                            }
                            setState(() {
                              _selectedPreset = value;
                            });
                          },
                  ),
                ),
              ),
            ),
            SwitchListTile(
              title: const Text('Require Rust init (fail fast)'),
              subtitle: const Text(
                'When enabled, benchmark stops immediately if Rust channel init fails.',
              ),
              value: _requireRust,
              onChanged: _running
                  ? null
                  : (value) {
                      setState(() {
                        _requireRust = value;
                      });
                    },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _running ? null : _runPreset,
                      icon: _running
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow),
                      label: Text(
                        _running ? 'Running...' : 'Run local benchmark',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: _running || _uploading
                        ? null
                        : () {
                            setState(() {
                              _logText = '';
                              _lastReport = null;
                            });
                          },
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _uploadUrlController,
                enabled: !_running && !_uploading,
                decoration: const InputDecoration(
                  labelText: 'Upload URL',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 132,
                    child: TextField(
                      controller: _uploadFieldController,
                      enabled: !_running && !_uploading,
                      decoration: const InputDecoration(
                        labelText: 'Form field',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _running || _uploading || report == null
                          ? null
                          : _uploadLastReport,
                      icon: _uploading
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_upload_outlined),
                      label: Text(
                        _uploading ? 'Uploading...' : 'Upload last report',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (report != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Last run: ${report.config.scenario.cliName}, '
                  'wallClock=${report.wallClockDuration.inMilliseconds}ms',
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  _logText.isEmpty ? '[example] log is empty' : _logText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RunPreset {
  final String label;
  final BenchmarkConfig config;

  const _RunPreset({required this.label, required this.config});
}
