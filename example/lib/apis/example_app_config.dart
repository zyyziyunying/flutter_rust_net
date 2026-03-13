import 'package:flutter_rust_net/flutter_rust_net.dart';
import 'package:flutter_rust_net/network/benchmark/network_benchmark_harness.dart';

import 'request_lab_models.dart';

const String _kRequestBaseUrl = String.fromEnvironment(
  'FRN_EXAMPLE_REQUEST_BASE_URL',
  defaultValue: 'https://httpbin.org',
);
const String _kBenchmarkUploadUrl = String.fromEnvironment(
  'FRN_EXAMPLE_UPLOAD_URL',
  defaultValue: 'http://47.110.52.208:7777/upload',
);
const String _kBenchmarkUploadField = String.fromEnvironment(
  'FRN_EXAMPLE_UPLOAD_FIELD',
  defaultValue: 'file',
);
const String _kBenchmarkLoginPath = String.fromEnvironment(
  'FRN_EXAMPLE_LOGIN_PATH',
  defaultValue: '/user/login',
);
const String _kBenchmarkLoginUsername = String.fromEnvironment(
  'FRN_EXAMPLE_LOGIN_USERNAME',
  defaultValue: 'ziyunying',
);
const String _kBenchmarkLoginPassword = String.fromEnvironment(
  'FRN_EXAMPLE_LOGIN_PASSWORD',
  defaultValue: '123456',
);

// Centralized example defaults. Override with --dart-define at launch time.
const ExampleAppConfig kExampleAppConfig = ExampleAppConfig(
  requestLab: RequestLabPageConfig(
    defaultBaseUrl: _kRequestBaseUrl,
    presets: _kRequestPresets,
  ),
  benchmark: BenchmarkPageConfig(
    runPresets: _kBenchmarkRunPresets,
    upload: BenchmarkUploadConfig(
      uploadUrl: _kBenchmarkUploadUrl,
      fieldName: _kBenchmarkUploadField,
      loginPath: _kBenchmarkLoginPath,
      username: _kBenchmarkLoginUsername,
      password: _kBenchmarkLoginPassword,
      defaultFields: <String, String>{'source': 'flutter_rust_net_example'},
    ),
  ),
);

const List<RequestPreset> _kRequestPresets = [
  RequestPreset(
    label: 'HTTPBin GET',
    method: NetHttpMethod.get,
    url: '/get',
    queryText: 'source=flutter_rust_net_example\nchannel=auto',
    routeMode: RequestRouteMode.auto,
  ),
  RequestPreset(
    label: 'HTTPBin POST JSON',
    method: NetHttpMethod.post,
    url: '/post',
    headersText: 'content-type: application/json',
    bodyMode: RequestBodyMode.json,
    bodyText:
        '{\n  "source": "flutter_rust_net_example",\n  "message": "edit me"\n}',
    routeMode: RequestRouteMode.rust,
    enableFallback: true,
  ),
  RequestPreset(
    label: 'Relative Path Demo',
    method: NetHttpMethod.get,
    url: '/anything/example/demo',
    headersText: 'accept: application/json',
    expectLargeResponse: true,
  ),
];

const List<BenchmarkRunPreset> _kBenchmarkRunPresets = [
  BenchmarkRunPreset(
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
  BenchmarkRunPreset(
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
  BenchmarkRunPreset(
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

class ExampleAppConfig {
  final RequestLabPageConfig requestLab;
  final BenchmarkPageConfig benchmark;

  const ExampleAppConfig({required this.requestLab, required this.benchmark});
}

class RequestLabPageConfig {
  final String defaultBaseUrl;
  final List<RequestPreset> presets;

  const RequestLabPageConfig({
    required this.defaultBaseUrl,
    required this.presets,
  });

  RequestPreset get initialPreset => presets.first;
}

class BenchmarkPageConfig {
  final List<BenchmarkRunPreset> runPresets;
  final BenchmarkUploadConfig upload;

  const BenchmarkPageConfig({required this.runPresets, required this.upload});

  BenchmarkRunPreset get initialPreset => runPresets.first;
}

class BenchmarkUploadConfig {
  final String uploadUrl;
  final String fieldName;
  final String loginPath;
  final String username;
  final String password;
  final Map<String, String> defaultFields;

  const BenchmarkUploadConfig({
    required this.uploadUrl,
    required this.fieldName,
    required this.loginPath,
    required this.username,
    required this.password,
    this.defaultFields = const <String, String>{},
  });
}

class BenchmarkRunPreset {
  final String label;
  final BenchmarkConfig config;

  const BenchmarkRunPreset({required this.label, required this.config});
}
