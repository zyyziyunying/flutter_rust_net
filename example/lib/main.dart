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
  bool _running = false;
  bool _requireRust = false;
  String _logText =
      'Tap "Run local benchmark". The benchmark spins up a local loopback '
      'server automatically.';
  BenchmarkReport? _lastReport;

  @override
  void initState() {
    super.initState();
    _selectedPreset = _presets.first;
  }

  Future<void> _runPreset() async {
    if (_running) {
      return;
    }

    final buffer = StringBuffer();
    void appendLog(String message) {
      buffer.writeln(message);
      if (!mounted) {
        return;
      }
      setState(() {
        _logText = buffer.toString();
      });
    }

    setState(() {
      _running = true;
      _lastReport = null;
      _logText = '[example] starting ${_selectedPreset.label}';
    });

    try {
      final config = _selectedPreset.config.copyWith(requireRust: _requireRust);
      appendLog('[example] requireRust=$_requireRust');
      final report = await runNetworkBenchmark(config, log: appendLog);
      appendLog('');
      appendLog(report.toPrettyText());
      final compareSummary = _buildCompareSummary(report);
      if (compareSummary != null) {
        appendLog(compareSummary);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _lastReport = report;
      });
    } catch (error) {
      appendLog('[example] failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
        });
      }
    }
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
                    onPressed: _running
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
