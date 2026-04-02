# flutter_rust_net

`flutter_rust_net` is a thin Flutter network gateway that combines:

- Dart gateway/routing/fallback (`NetworkGateway`)
- `rhttp` primary request adapter (`RhttpAdapter`)
- Dio fallback + transfer adapter (`DioAdapter`)
- Legacy FRB bridge files and `native/rust/net_engine` for retained compatibility/testing surfaces

## What this package provides

- Unified request and transfer task abstractions (`NetRequest`, `NetResponse`, `NetTransferTaskRequest`)
- HTTP method/header enums for safer callsites (`NetHttpMethod`, `NetHeaderName`)
- Route policy + feature flags (`RoutingPolicy`, `NetFeatureFlag`)
- `rhttp + Dio` dual-channel request execution with controlled fallback
- Dio-only transfer execution in thin-gateway V1
- Bytes-first client utilities (`BytesFirstNetworkClient`, including `standard()` factory)

## Legacy Rust bridge integration

The checked-in Rust dynamic library and FRB bindings remain in the repository
for legacy `RustAdapter` compatibility/testing flows. The normal V1 request path
does not require `RustAdapter.initializeEngine()` or a locally built
`native/rust/net_engine`.

Legacy bridge-backed flows expect the Rust dynamic library built from:

- `native/rust/net_engine` (relative to this repository root)

Runtime loading is handled by `FrbRustBridgeApi` and falls back to local debug/release library paths when default loading fails.

Regenerate bindings and rebuild the host library from the package root with:

```bash
dart run tool/rust_codegen.dart
dart run tool/rust_build.dart --profile=release
```

If you hit `Detected stale net_engine native library`, the checked-in/generated Rust sources are newer than the local dynamic library. Rebuild before running legacy bridge tests or other real-bridge flows:

```bash
dart run tool/rust_build.dart --profile=release
```

This usually happens after editing `native/rust/net_engine`, rerunning FRB codegen, or switching to a branch with Rust-side changes.

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
// Safe default: stays on Dio until you opt into the primary request channel.
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

To enable the primary request channel in V1, use the compatibility-name helper.
This uses `rhttp` under the hood and does not require manual engine lifecycle:

```dart
final client = await BytesFirstNetworkClient.standardWithRust();
```

Equivalent manual wiring:

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

`NetRequest` and `NetTransferTaskRequest` also accept `baseUrl` for per-request
overrides. The gateway resolves relative URLs before routing/fallback so Dio and
Rust channels see the same absolute URL.

Transfer tasks remain Dio-only in thin-gateway V1. If you force
`NetChannel.rust` for transfer APIs, the gateway fails explicitly instead of
silently rerouting.

Legacy bridge-backed compatibility:

```dart
final rustAdapter = RustAdapter();
await rustAdapter.initializeEngine();
// ... legacy bridge-backed request/transfer/test flow ...
await rustAdapter.shutdownEngine();
```

Use `RustAdapter.initializeEngine()` / `shutdownEngine()` only when you
explicitly opt into the retained legacy bridge path. The constructor
`initialized` flag and `markInitialized()` are intended only for
`requestHandler`-backed test doubles, not bridge-backed adapters.

`body` uses one shared contract on both Dio and Rust channels:

- `bodyBytes`: sent as raw bytes
- `String`: sent as UTF-8 bytes
- other JSON-encodable objects, including `List<int>` JSON arrays: sent as UTF-8 JSON bytes

The package does not infer or rewrite `content-type`; set it explicitly when the server depends on it.
