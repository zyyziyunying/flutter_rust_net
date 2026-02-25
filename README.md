# flutter_rust_net

`flutter_rust_net` is an extracted Flutter network layer that combines:

- Dart gateway/routing/fallback (`NetworkGateway`)
- Dio adapter (`DioAdapter`)
- Rust adapter via flutter_rust_bridge (`RustAdapter`)
- Generated FRB bridge files for `native/rust/net_engine`

## What this package provides

- Unified request and transfer task abstractions (`NetRequest`, `NetResponse`, `NetTransferTaskRequest`)
- Route policy + feature flags (`RoutingPolicy`, `NetFeatureFlag`)
- Dio/Rust dual-channel execution with controlled fallback
- Bytes-first client utilities (`BytesFirstNetworkClient`)

## Rust integration

This package expects the Rust dynamic library built from:

- `../native/rust/net_engine` (relative to this repository root)

Runtime loading is handled by `FrbRustBridgeApi` and falls back to local debug/release library paths when default loading fails.

## Standalone example (recommended for local device validation)

- Example app: `flutter_rust_net/example/`
- Android Rust `.so` build wiring: `flutter_rust_net/example/android/app/build.gradle.kts`
- Example app log view also mirrors benchmark logs to console (`debugPrint`) for easier troubleshooting.

Run:

```bash
cd flutter_rust_net/example
flutter pub get
flutter run
```

## Quick usage

```dart
final gateway = NetworkGateway(
  routingPolicy: const RoutingPolicy(),
  featureFlag: const NetFeatureFlag(enableRustChannel: true),
  dioAdapter: DioAdapter(),
  rustAdapter: RustAdapter(),
);
```
