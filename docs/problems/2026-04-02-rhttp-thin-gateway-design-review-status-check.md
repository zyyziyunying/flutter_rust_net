# Rhttp Thin Gateway Design Review Status Check

> Date: 2026-04-02
> Checked against: `docs/archived/2026-04-01-rhttp-thin-gateway-design-review.md`
> Scope: current worktree status check only

## Verdict

The highest-value thin-gateway V1 issues from the original design review are
closed in the current worktree, but full real-`rhttp` verification is still
not part of the default test environment.

Current state:

- key request-path implementation changes are in place
- the matching design / overview docs now reflect the V1 boundary
- the root barrel still exposes the retained legacy `RustAdapter` compatibility
  surface
- targeted Flutter test verification completed successfully in the current
  environment
- real-`rhttp` tests remain opt-in because they require a local
  `librhttp.dylib`

## Resolved In Code

### 1. `standardWithRust()` is now a V1 compatibility shim

Evidence:

- `lib/network/bytes_first_network_client.dart`
  - `BytesFirstNetworkClient.standard()`
  - `BytesFirstNetworkClient.standardWithRust()`
  - `BytesFirstNetworkClient.rustAdapter`
- `test/network/bytes_first_network_client_test.dart`

Status:

- Resolved in implementation.
- Default primary request routing now uses `RhttpAdapter`.
- `standardWithRust()` is retained only as a deprecated compatibility helper.
- It no longer auto-initializes legacy `RustAdapter`.
- The legacy-shaped getter now only returns explicitly injected `RustAdapter`
  instances.

### 2. Request-body contract is still centralized through `encodeRequestBody()`

Evidence:

- `lib/network/request_body_codec.dart`
- `lib/network/dio_adapter.dart`
- `lib/network/rhttp_adapter.dart`
- `test/network/request_body_channel_consistency_test.dart`

Status:

- Resolved in implementation.
- Both Dio and `RhttpAdapter` reuse the same request-body normalization entry
  point.
- The request path still preserves the bytes-first contract and does not
  intentionally rewrite `content-type`.

### 3. Transfer routing is now explicitly Dio-only in V1

Evidence:

- `lib/network/network_gateway.dart`
- `test/network/network_gateway/network_gateway_transfer_task_test.dart`
- `README.md`

Status:

- Resolved in implementation.
- Transfer start / poll / cancel stay on Dio in V1.
- Forcing `NetChannel.rust` on transfer now fails explicitly instead of silently
  pretending to use the Rust path.

## Resolved Since The Original Review

### 1. Readiness behavior and design-doc wording are now aligned

Evidence:

- `lib/network/rhttp_adapter.dart`
  - `RhttpAdapter.isReady`
  - `ensureRequestReady()`
- `lib/network/network_gateway.dart`
  - `_isRustRequestReady()`
  - `request()`
- `docs/plan/2026-04-01-flutter-rust-net-rhttp-thin-gateway-design.md`
  - Readiness model section now describes request-path availability as real
    runtime state and requires request preflight before primary routing

Status:

- Resolved in the current worktree.
- The implementation no longer treats readiness as “always true”.
- `NetworkGateway.request()` now does a real request-path preflight before
  routing into the primary adapter.
- The design doc now matches the implemented readiness model.

### 2. Overview / example-facing V1 request-path wording is now aligned

Evidence:

- `FLUTTER_RUST_NET_OVERVIEW_ZH.md`
  - now says the V1 request path returns `bytes`
  - now says `expectLargeResponse` is compatibility-only in thin-gateway V1
- `lib/network/net_models.dart`
  - V1 comments state `expectLargeResponse` is compatibility-only
  - `bodyFilePath` remains `null`
  - `fromCache` remains `false`
- `example/lib/pages/request_lab_page.dart`
  - Request Lab now correctly labels `expectLargeResponse` as a V1 no-op

Status:

- Resolved in the current worktree.
- The implementation, overview doc, and request-lab copy now agree on the V1
  bytes-first request boundary.
- Request-path file-backed output is no longer described as an active V1
  behavior.

### 3. Root barrel compatibility for retained legacy `RustAdapter` is intact

Evidence:

- `lib/flutter_rust_net.dart`
- `README.md`
- `docs/problems/archive/2026-04-02-task-4-5-thin-gateway-v1-code-review.md`

Status:

- Resolved in the current worktree.
- The package root barrel exports both `network/rhttp_adapter.dart` and the
  retained legacy `network/rust_adapter.dart`.
- Consumers importing only `package:flutter_rust_net/flutter_rust_net.dart`
  can still access `RustAdapter` through the root barrel.

## Still Not Fully Closed

### 1. Real-`rhttp` coverage still depends on opt-in native-library setup

Severity: Low

Evidence:

- `test/network/rhttp_adapter_test.dart`
  - real-`rhttp` cases are skipped unless
    `FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR` points to
    `librhttp.dylib`
- `test/network/request_body_channel_consistency_test.dart`
  - real-`rhttp` parity cases use the same environment gate

Problem:

- Default `flutter test` coverage validates the seam-backed adapter path, the
  gateway behavior, and the surrounding request-path contract.
- But the higher-fidelity real-`rhttp` cases still require explicit local
  native-library setup and are skipped otherwise.

Impact:

- The current worktree has fresh package-test evidence for the V1 request path.
- But it still does not prove that the real native `rhttp` path was exercised
  in a default environment without extra setup.

## Verification Limitation

### 1. Targeted `flutter test` verification completed in this environment

Attempted command:

```bash
flutter test \
  test/network/bytes_first_network_client_test.dart \
  test/network/network_gateway/network_gateway_request_test.dart \
  test/network/network_gateway/network_gateway_transfer_task_test.dart \
  test/network/request_body_channel_consistency_test.dart \
  test/network/rhttp_adapter_test.dart \
  test/network/benchmark_runner_test.dart
```

Observed result:

- the command completed successfully with exit code `0`
- the targeted package tests passed in this environment
- real-`rhttp` tests were skipped because
  `FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR` was not configured with a
  local `librhttp.dylib`
- no `package:sqlite3` native-asset failure occurred in this verification run

Why this matters:

- This provides fresh local evidence that the remaining V1 request-path package
  tests currently pass.
- The only missing part is opt-in real-`rhttp` execution, which remains gated
  by local native-library setup rather than by a package-test failure.

## Practical Conclusion

The original design review is not “fully cleared”.

What can be said accurately:

- the core V1 runtime changes are implemented
- the highest-value request-path fixes are present in code and reflected in the
  current design / overview docs
- the retained legacy `RustAdapter` compatibility surface is still exported
- fresh local package-test evidence exists for the targeted V1 request-path
  suite
- the remaining limitation is that real-`rhttp` execution still requires
  opt-in local native-library setup
