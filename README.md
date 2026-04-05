# flutter_rust_net

`flutter_rust_net` is a thin Flutter network gateway built around:

- `NetworkGateway` for routing and fallback
- `RhttpAdapter` as the primary request path
- `DioAdapter` as the fallback request path and the V1 transfer path

## What this package provides

- Unified request and transfer task abstractions (`NetRequest`, `NetResponse`, `NetTransferTaskRequest`)
- HTTP method/header enums for safer callsites (`NetHttpMethod`, `NetHeaderName`)
- Route policy + feature flags (`RoutingPolicy`, `NetFeatureFlag`)
- `rhttp + Dio` dual-channel request execution with controlled fallback
- Dio-only transfer execution in thin-gateway V1
- Bytes-first client utilities (`BytesFirstNetworkClient`, including `standard()`)

## Compatibility naming

This hard cut intentionally keeps these compatibility names:

- `NetChannel.rust`
- `enableRustChannel`
- `BenchmarkChannel.rust`

They now mean "use the primary request channel", not "use a package-local FRB/runtime stack".

## Standalone example

- Example app: `flutter_rust_net/example/`
- Tabs:
  - `Request Lab`: manual API testing with Dio/primary-channel routing controls
  - `Benchmark`: local loopback benchmark + report upload
- Default request/upload/login settings live in `example/lib/apis/example_app_config.dart`

Run:

```bash
cd flutter_rust_net/example
flutter pub get
flutter run
```

## Quick usage

```dart
final client = BytesFirstNetworkClient.standard();

final response = await client.request(
  method: NetHttpMethod.post,
  url: 'https://example.com/upload',
  headers: {
    NetHeaderName.contentType.wireName: 'application/json',
  },
  bodyBytes: bytes,
);
```

Enable the primary request channel with the compatibility-named flag:

```dart
final client = BytesFirstNetworkClient.standard(
  featureFlag: const NetFeatureFlag(enableRustChannel: true),
);
```

Or configure a client-level `baseUrl` and send relative paths:

```dart
final client = BytesFirstNetworkClient.standard(
  baseUrl: 'https://example.com/api',
);

final response = await client.request(
  method: NetHttpMethod.get,
  url: '/feed',
);
```

`NetRequest` and `NetTransferTaskRequest` also accept `baseUrl` for per-request overrides. The gateway resolves relative URLs before routing/fallback so Dio and primary-channel requests see the same absolute URL.

Transfer tasks remain Dio-only in thin-gateway V1. If you force `NetChannel.rust` for transfer APIs, the gateway fails explicitly instead of silently rerouting.

`body` uses one shared contract on both Dio and primary-channel requests:

- `bodyBytes`: sent as raw bytes
- `String`: sent as UTF-8 bytes
- Other JSON-encodable objects, including `List<int>` JSON arrays: sent as UTF-8 JSON bytes

The package does not infer or rewrite `content-type`; set it explicitly when the server depends on it.

## Benchmark and validation

- `dart run tool/network_bench.dart --help` shows the local benchmark CLI.
- `dart run tool/p1_non_loopback_bench.dart --help` runs the fixed public-remote benchmark lane.
- Package baseline verification is `flutter test`.
- Some real-`rhttp` tests remain opt-in when local native `rhttp` prerequisites are not prepared; do not claim that lane unless it was actually run.
