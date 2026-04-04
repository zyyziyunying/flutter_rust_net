# Remove FRB Hard-Cut Resequenced Plan

> Date: 2026-04-04
> Status: Current execution plan
> Basis:
> - `docs/plan/2026-04-02-remove-frb-and-legacy-rust-surface-implementation-plan.md`
> - `docs/plan/2026-04-01-flutter-rust-net-rhttp-thin-gateway-design.md`
> - current worktree inspection
> - multi-agent review on runtime/API, benchmark/tooling, and validation/docs

## Goal

Complete the FRB hard cut without breaking the already-landed thin-gateway V1
request path.

After this change, `flutter_rust_net` should be described and implemented as:

- `rhttp` primary request path
- Dio fallback path
- Dio-only transfer path
- no package-local FRB/runtime/native-engine dependency in the active package

## Why This Revision Exists

The 2026-04-02 hard-cut plan got the overall direction right, but its task
sequence no longer matches the current repository state.

The main issue is ordering:

- benchmark/runtime code still imports Rust-specific types and test doubles
- active docs/progress files still describe FRB/Rust state as current fact
- deleting runtime files first would break benchmark compilation before the
  benchmark cleanup lands

This revised plan keeps the same destination but changes the execution order.

## Binding Decisions

### 1. Surviving compatibility contract

Keep these compatibility names in this cut:

- `NetChannel.rust`
- `enableRustChannel`
- `BenchmarkChannel.rust`

Their meaning remains "primary native-backed request channel", not
"legacy FRB/net_engine request path".

### 2. Public seam cleanup

Do not keep business-facing legacy seams that imply FRB ownership.

Target outcome:

- remove `standardWithRust()`
- remove public/runtime `RustAdapter` and `RustBridgeApi` usage
- stop exposing benchmark/runtime inputs such as `rustBridgeApi`
- stop exposing engine-specific knobs that no longer affect the V1 request path

Test-only injection may remain where necessary, but it should use neutral
adapter seams instead of legacy `rustAdapter`-shaped public promises.

### 3. Validation claim after hard cut

Do not overstate verification.

Post-cut validation must explicitly distinguish:

- package baseline: targeted `flutter test` and full `flutter test`
- optional high-fidelity lane: real-`rhttp` verification if still available

If the real-`rhttp` lane remains opt-in, docs must say so directly instead of
implying it is covered by the default lane.

### 4. Historical evidence boundary

Existing P1/P2 Rust/FRB/cache evidence remains useful as history, but it must
be relabeled as legacy-path or pre-hard-cut evidence once FRB is removed.

## Execution Order

### Phase 1: Freeze the surviving contract first

Scope:

- `lib/network/bytes_first_network_client.dart`
- `lib/network/network_gateway.dart`
- `test/network/bytes_first_network_client_test.dart`
- `test/network/network_gateway/network_gateway_request_test.dart`
- `test/network/network_gateway/network_gateway_transfer_task_test.dart`
- `test/flutter_rust_net_test.dart`

Actions:

- lock the supported client/gateway contract to thin-gateway V1 semantics
- remove stale test expectations around `standardWithRust()` or legacy exports
- decide and implement the public fate of injectable primary-adapter seams

Acceptance:

- request and transfer contract tests pass
- no active test treats FRB lifecycle as part of the normal request happy path

### Phase 2: Remove benchmark/runtime compile dependencies before file deletion

Scope:

- `lib/network/benchmark/benchmark_config.dart`
- `lib/network/benchmark/benchmark_runner.dart`
- `lib/network/benchmark/benchmark_report.dart`
- `lib/network/benchmark/benchmark_enums.dart`
- `test/network/benchmark_runner_test.dart`
- `test/network/benchmark_types_test.dart`
- `test/network/network_realistic_flow_test.dart`

Actions:

- remove `RustEngineInitOptions` and other Rust-runtime compile dependencies
- remove `rustBridgeApi` from benchmark-facing APIs
- remove stale knobs:
  - `initializeRust`
  - `requireRust`
  - `rustMaxInFlightTasks`
  - `rustCache*`
- keep `BenchmarkChannel.rust` as a compatibility alias for the primary request
  channel

Acceptance:

- benchmark library code compiles without importing FRB/runtime Dart files
- benchmark tests no longer depend on generated FRB API or fake Rust bridge
  types

### Phase 3: Delete Dart-side legacy runtime and rewrite/delete dependent tests in the same change

Scope:

- `lib/network/rust_adapter.dart`
- `lib/network/rust_bridge_api.dart`
- `lib/network/rust_adapter/`
- `lib/rust_bridge/`
- `test/network/rust_adapter/`
- `test/network/rust_adapter_lifecycle_test.dart`
- `test/network/rust_adapter_real_bridge_test.dart`
- `test/network/rust_adapter_shared_scope_test.dart`
- `test/network/rust_bridge_api_test.dart`
- `test/network/network_smoke_flow_test.dart`

Actions:

- delete the legacy runtime code
- delete or rewrite tests that directly construct `RustAdapter` or depend on
  FRB-specific behavior
- keep only tests that validate the surviving `rhttp + Dio` contract

Acceptance:

- package compiles after physical deletion of runtime/FRB Dart files
- surviving request/gateway/benchmark tests still pass

### Phase 4: Clean example, CLI, and P1 tooling in the same benchmark slice

Scope:

- `tool/network_bench.dart`
- `tool/p1_non_loopback_bench.dart`
- `tool/p1_aggregate/`
- `example/lib/apis/example_app_config.dart`
- `example/lib/pages/benchmark_page.dart`

Actions:

- remove CLI/UI wording that still says "Require Rust" or equivalent
- keep channel-compare behavior but stop pretending the old engine is present
- either update P1 aggregation schema away from `rustMaxInFlightTasks` and
  related fields, or explicitly archive those tools if they are no longer
  current

Acceptance:

- example and tooling no longer expose dead FRB/net_engine controls
- active benchmark UX describes the primary channel accurately

### Phase 5: Remove dependency, native project, and build tooling

Scope:

- `pubspec.yaml`
- `flutter_rust_bridge.yaml`
- `tool/rust_codegen.dart`
- `tool/rust_build.dart`
- `native/rust/net_engine/`
- `example/android/app/build.gradle.kts`
- `example/README.md`

Actions:

- remove `flutter_rust_bridge` from dependencies
- delete package-local Rust build/codegen tooling
- delete the package-local native engine
- remove example Android Rust build wiring

Acceptance:

- package `flutter pub get` passes
- example `flutter pub get` passes
- remaining tree contains no active FRB/native-engine build workflow

### Phase 6: Update active docs and progress files in the same removal window

Scope:

- `README.md`
- `FLUTTER_RUST_NET_OVERVIEW_ZH.md`
- `docs/README.md`
- `docs/flutter_rust_network_layer_design.md`
- `docs/problems/2026-04-02-project-progress-and-gap-assessment.md`
- `docs/problems/2026-04-02-rhttp-thin-gateway-design-review-status-check.md`
- `docs/progress/README.md`
- `docs/progress/p1_status_2026-02-25.md`
- `docs/progress/p2_status_2026-03-02.md`
- `docs/progress/rust_lifecycle_scope_status_2026-03-12.md`
- `docs/progress/real_device_test_commands_2026-03-02.md`
- `docs/plan/README.md`

Actions:

- remove current-state wording that still presents FRB/Rust runtime as active
- mark older P1/P2 Rust/cache evidence as historical or legacy-path-only
- stop active entry-point docs from routing readers into stale architecture
  descriptions as if they were current

Acceptance:

- active docs no longer describe FRB/net_engine as part of the package's
  current contract
- active docs make the post-hard-cut validation boundary explicit

## Verification Order

Use narrow verification after each phase instead of waiting for one final run.

Recommended order:

1. targeted client/gateway tests
2. targeted benchmark tests
3. package `flutter pub get`
4. full `flutter test`
5. example `flutter pub get`

Optional lane:

- real-`rhttp` verification if local native prerequisites still apply

Do not claim this optional lane was covered unless it was actually run.

## Explicit Non-Goals For This Cut

- rename `NetChannel.rust`, `enableRustChannel`, or `BenchmarkChannel.rust`
- redesign the benchmark product surface beyond removing dead engine-specific
  knobs
- reopen old Rust cache/root-budget work as current package value
- run `flutter analyze` by default

## Exit Criteria

This plan is complete when:

- the package no longer depends on FRB or `native/rust/net_engine`
- the package still exposes a coherent `rhttp + Dio` thin-gateway contract
- benchmark/example/tooling no longer advertise dead Rust-engine controls
- active docs and progress files no longer describe removed runtime pieces as
  current truth
- verification claims match what was actually exercised
