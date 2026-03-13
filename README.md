# flutter_rust_net

`flutter_rust_net` is an extracted Flutter network layer that combines:

- Dart gateway/routing/fallback (`NetworkGateway`)
- Dio adapter (`DioAdapter`)
- Rust adapter via flutter_rust_bridge (`RustAdapter`)
- Generated FRB bridge files for package-local `native/rust/net_engine`

## What this package provides

- Unified request and transfer task abstractions (`NetRequest`, `NetResponse`, `NetTransferTaskRequest`)
- HTTP method/header enums for safer callsites (`NetHttpMethod`, `NetHeaderName`)
- Route policy + feature flags (`RoutingPolicy`, `NetFeatureFlag`)
- Dio/Rust dual-channel execution with controlled fallback
- Bytes-first client utilities (`BytesFirstNetworkClient`, including `standard()` factory)

## Rust integration

This package expects the Rust dynamic library built from:

- `native/rust/net_engine` (relative to this repository root)

Runtime loading is handled by `FrbRustBridgeApi` and falls back to local debug/release library paths when default loading fails.

## Standalone example (recommended for local device validation)

- Example app: `flutter_rust_net/example/`
- Android Rust `.so` build wiring: `flutter_rust_net/example/android/app/build.gradle.kts`
- The example app now has two tabs:
  - `Request Lab`: manual API testing with editable method/url/header/body and Dio/Rust routing controls
  - `Benchmark`: local loopback benchmark + report upload
- Default request/upload/login settings are centralized in `example/lib/apis/example_app_config.dart` and can be overridden with `--dart-define`.
- Example app log views also mirror request / benchmark logs to console (`debugPrint`) for easier troubleshooting.

Run:

```bash
cd flutter_rust_net/example
flutter pub get
flutter run
```

## Quick usage

```dart
// Safe default: stays on Dio until you opt into Rust explicitly.
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

To enable Rust routing, initialize the adapter up front instead of relying on
runtime readiness fallback:

```dart
final client = await BytesFirstNetworkClient.standardWithRust();
```

Equivalent manual wiring:

```dart
final rustAdapter = RustAdapter();
await rustAdapter.initializeEngine();

final client = BytesFirstNetworkClient.standard(
  featureFlag: const NetFeatureFlag(enableRustChannel: true),
  rustAdapter: rustAdapter,
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

`NetRequest` and `NetTransferTaskRequest` also accept `baseUrl` for per-request
overrides. The gateway resolves relative URLs before routing/fallback so Dio and
Rust channels see the same absolute URL.

Supported lifecycle usage:

```dart
await rustAdapter.shutdownEngine();
```

Use `RustAdapter.initializeEngine()` / `shutdownEngine()` as the supported
lifecycle API. Avoid calling the generated FRB `shutdownNetEngine()` directly,
because that bypasses Dart-side shared-scope lifecycle tracking.
The constructor `initialized` flag and `markInitialized()` are intended only
for `requestHandler`-backed test doubles, not bridge-backed adapters.
`RustEngineInitOptions.baseUrl` remains available for Rust-engine-specific
compatibility, but cross-channel code should prefer the request/client
`baseUrl` API above.

`body` uses one shared contract on both Dio and Rust channels:

- `bodyBytes`: sent as raw bytes
- `String`: sent as UTF-8 bytes
- other JSON-encodable objects, including `List<int>` JSON arrays: sent as UTF-8 JSON bytes

The package does not infer or rewrite `content-type`; set it explicitly when the server depends on it.
