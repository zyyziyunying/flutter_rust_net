---
title: Task 4/5 Thin Gateway V1 Code Review Findings
status: resolved
---

# Task 4/5 Thin Gateway V1 Code Review Findings

> Date: 2026-04-02
> Scope: Task 4/5 implementation review for thin gateway V1 only
> Reviewed worktree files:
> - `lib/network/bytes_first_network_client.dart`
> - `lib/flutter_rust_net.dart`
> - `lib/network/benchmark/benchmark_runner.dart`
> - `example/lib/pages/request_lab_page.dart`
> - `example/lib/pages/benchmark_page.dart`
> - `README.md`
> - `FLUTTER_RUST_NET_OVERVIEW_ZH.md`
> - `docs/plan/2026-04-01-flutter-rust-net-rhttp-thin-gateway-design.md`
> - `test/network/bytes_first_network_client_test.dart`
> - `test/network/benchmark_runner_test.dart`
> - `example/test/widget_test.dart`

## Review Result

Main V1 boundary is mostly aligned:

- request path = `rhttp + Dio fallback`
- transfer path = Dio-only
- `standard()` remains Dio-safe by default
- `standardWithRust()` no longer initializes legacy `RustAdapter`
- example request happy path no longer manually manages Rust engine lifecycle

The remaining issues are below.

## High Severity Findings

### 1. Root barrel no longer exports retained legacy compat surface, causing source break

Evidence:

- `lib/flutter_rust_net.dart:1-9`
- `README.md:117-129`
- `test/flutter_rust_net_test.dart:6-28`

Problem:

- `lib/flutter_rust_net.dart` no longer exports `network/rust_adapter.dart`.
- The docs still describe `RustAdapter` as a retained compatibility/testing surface.
- Consumers importing only `package:flutter_rust_net/flutter_rust_net.dart` can no longer access `RustAdapter` or `RustEngineInitOptions`.

Why this matters:

- This is a real source break, not just a doc mismatch.
- It conflicts with the stated transition strategy of keeping legacy bridge surfaces for compatibility/testing flows.

Recommended fix:

- Either restore the root export for the retained legacy surface, or explicitly document and test that root-barrel access is no longer supported.
- Add a regression test that imports only `package:flutter_rust_net/flutter_rust_net.dart` and references the intended retained compat symbols.

### 2. `runNetworkBenchmark()` still exposes `rustBridgeApi`, but now silently ignores it

Evidence:

- `lib/network/benchmark/benchmark_runner.dart:18-23`
- `lib/network/benchmark/benchmark_runner.dart:44-52`
- `test/network/benchmark_runner_test.dart:31-40`
- `test/network/benchmark_runner_test.dart:63-77`

Problem:

- `runNetworkBenchmark()` still accepts `rustBridgeApi`.
- The implementation now always defaults to `RhttpAdapter()` unless a separate `rustAdapter` is injected.
- When `rustBridgeApi` is passed alone, the runner only logs that it is ignored.

Why this matters:

- This is hidden API drift for existing benchmark callers that previously used `rustBridgeApi` as the Rust-path injection seam.
- The new tests do not catch it because they always pass both `rustBridgeApi` and `rustAdapter`.

Recommended fix:

- Either remove/deprecate `rustBridgeApi` on this V1 runner surface, or keep a compatible behavior contract instead of silently ignoring it.
- Add a regression test for `runNetworkBenchmark(config, rustBridgeApi: ...)` without `rustAdapter`.

## Medium Severity Findings

### 3. Request Lab still describes `expectLargeResponse` as file-backed Rust behavior

Evidence:

- `example/lib/pages/request_lab_page.dart:546-560`
- `docs/plan/2026-04-01-flutter-rust-net-rhttp-thin-gateway-design.md:158-160`
- `docs/plan/2026-04-01-flutter-rust-net-rhttp-thin-gateway-design.md:274-277`

Problem:

- The UI still says `Expect large response` is a Rust transport hint for file-backed large bodies.
- The current V1 contract says request-path `expectLargeResponse` is kept only as a compatibility no-op, `bodyFilePath` stays `null`, and `fromCache` stays `false`.

Why this matters:

- This misleads manual validation in the example app.
- It suggests request-path file materialization still exists when V1 explicitly does not promise that behavior.

Recommended fix:

- Rewrite the Request Lab copy to state that the flag is retained for compatibility and currently does not change V1 request-path behavior.

### 4. Benchmark report still uses `rustInitialized` as a headline field even though it now only means optional preflight happened

Evidence:

- `lib/network/benchmark/benchmark_runner.dart:74-85`
- `lib/network/benchmark/benchmark_runner.dart:145-153`
- `lib/network/benchmark/benchmark_report.dart:43-53`
- `test/network/benchmark_runner_test.dart:79-85`
- `example/lib/pages/benchmark_page.dart:95-100`

Problem:

- `rustInitialized` is now set only when optional rust-channel preflight runs.
- A benchmark can still execute entirely on the rust request channel while `rustInitialized == false`.
- The example app prints `report.toPrettyText()` directly, so users will see this ambiguous field in the main report summary.

Why this matters:

- The report headline can now misstate what happened operationally.
- The new tests already lock in this ambiguity by asserting rust-channel success together with `rustInitialized == false`.

Recommended fix:

- Rename or redefine the field to match thin-gateway V1 semantics, for example “rustChannelPreflighted” or similar.
- If the field must stay for compatibility, document the narrowed meaning explicitly in report output and tests.

## Remaining Test Gaps

### 1. No root-barrel compat regression test

Current root export coverage only verifies common models:

- `test/flutter_rust_net_test.dart:6-28`

Missing:

- a test proving whether `RustAdapter` and related retained compat symbols are or are not intentionally available from the package root barrel

### 2. No benchmark compat regression for `rustBridgeApi`-only callers

Current benchmark tests cover:

- injected `RhttpAdapter` preflight without FRB lifecycle
- rust-path execution without explicit initialization

Missing:

- the old compat-shaped entry where a caller passes `rustBridgeApi` but does not inject a separate `rustAdapter`

### 3. No explicit test guarding V1 request metadata boundary in the public client path

The design requires:

- `expectLargeResponse` is a no-op
- `bodyFilePath` stays `null`
- `fromCache` stays `false`

There is coverage at adapter level, but the updated Task 4/5 tests do not add an explicit `BytesFirstNetworkClient` or example-facing regression test for that public V1 boundary.

## Notes

This review did not find additional problems with these specific V1 expectations:

- `BytesFirstNetworkClient.standard()` remains the Dio-safe default entry
- `enableRustChannel=true` defaults to `RhttpAdapter`
- `standardWithRust()` is now a V1 shim and no longer initializes legacy `RustAdapter`
- normal request happy path no longer requires business-side manual `RustAdapter.initializeEngine()`
