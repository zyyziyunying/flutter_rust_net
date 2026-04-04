# Remove FRB And Legacy Rust Surface Implementation Plan

> Superseded on 2026-04-04 by
> `docs/plan/2026-04-04-remove-frb-hard-cut-resequenced-plan.md`.
>
> This file is retained for review traceability because active review records in
> `docs/problems/2026-04-02-rhttp-dio-hard-cut-review-findings.md` reference it
> directly. Do not use this file as the current execution plan.

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Convert `flutter_rust_net` into a pure `rhttp + Dio` package by removing `flutter_rust_bridge`, package-local `net_engine`, and all public/runtime/tooling surfaces that still depend on them.

**Architecture:** The implementation should preserve the current thin-gateway request and transfer contract while deleting the unused legacy bridge path. Requests remain `RhttpAdapter` primary plus Dio fallback; transfers remain Dio-only. The cleanup should proceed in contract-first order: lock surviving behaviors in tests, remove legacy Dart surfaces, then remove benchmark/tooling/native baggage, and finally update docs and workspace instructions.

**Tech Stack:** Flutter/Dart, `dio`, `rhttp`, `flutter_test`, Gradle docs/config cleanup

**Commit Policy:** Commit strategy is intentionally omitted from this plan and
is managed by the executor.

---

### Task 1: Lock the surviving client and gateway contract

**Files:**
- Modify: `flutter_rust_net/test/network/bytes_first_network_client_test.dart`
- Modify: `flutter_rust_net/test/network/network_gateway/network_gateway_request_test.dart`
- Modify: `flutter_rust_net/test/network/network_gateway/network_gateway_transfer_task_test.dart`
- Modify: `flutter_rust_net/test/flutter_rust_net_test.dart`
- Modify: `flutter_rust_net/lib/network/bytes_first_network_client.dart`
- Modify: `flutter_rust_net/lib/flutter_rust_net.dart`

**Step 1: Update contract tests**

Update tests so the supported contract is explicit:

- `BytesFirstNetworkClient.standard()` remains the default constructor
- enabling `NetFeatureFlag(enableRustChannel: true)` uses the primary request path
- request helpers still preserve bytes-first behavior and route metadata
- transfer APIs still reject `forceChannel: NetChannel.rust`
- no test depends on `standardWithRust()`, `RustAdapter`, or `rustAdapter`

**Step 2: Run baseline targeted tests**

Run:

```bash
cd /Users/zyyziyunying/harrypet_flutter/flutter_rust_net && flutter test test/network/bytes_first_network_client_test.dart test/network/network_gateway/network_gateway_request_test.dart test/network/network_gateway/network_gateway_transfer_task_test.dart test/flutter_rust_net_test.dart
```

Expected: command runs and provides a concrete baseline for this task.
If failures appear, treat each failure as an explicit implementation gap list
for Step 3.

**Step 3: Write the minimal implementation**

Implement the contract cleanup:

- remove `standardWithRust()` from `BytesFirstNetworkClient`
- remove the legacy `rustAdapter` getter
- delete public exports for `rust_adapter.dart` and `rust_bridge_api.dart`
- keep `NetChannel.rust` and `enableRustChannel` semantics unchanged for the
  `rhttp` primary request path

**Step 4: Run tests to verify they pass**

Run:

```bash
cd /Users/zyyziyunying/harrypet_flutter/flutter_rust_net && flutter test test/network/bytes_first_network_client_test.dart test/network/network_gateway/network_gateway_request_test.dart test/network/network_gateway/network_gateway_transfer_task_test.dart test/flutter_rust_net_test.dart
```

Expected: PASS.

### Task 2: Remove Dart-side bridge/runtime code and legacy tests

**Files:**
- Delete: `flutter_rust_net/lib/network/rust_adapter.dart`
- Delete: `flutter_rust_net/lib/network/rust_bridge_api.dart`
- Delete: `flutter_rust_net/lib/network/rust_adapter/`
- Delete: `flutter_rust_net/lib/rust_bridge/`
- Delete: `flutter_rust_net/test/network/rust_adapter/`
- Delete: `flutter_rust_net/test/network/rust_adapter_lifecycle_test.dart`
- Delete: `flutter_rust_net/test/network/rust_adapter_real_bridge_test.dart`
- Delete: `flutter_rust_net/test/network/rust_adapter_shared_scope_test.dart`
- Delete: `flutter_rust_net/test/network/rust_bridge_api_test.dart`
- Modify or delete: `flutter_rust_net/test/network/network_smoke_flow_test.dart`

**Step 1: Update surviving contract tests**

Before deleting files, add or tighten remaining tests so they fully cover the
surviving request/transfer contract without any bridge dependencies:

- `RhttpAdapter` request behavior
- request body channel consistency
- Dio-only transfer behavior
- routing/fallback behavior

Use:

- `flutter_rust_net/test/network/rhttp_adapter_test.dart`
- `flutter_rust_net/test/network/request_body_channel_consistency_test.dart`
- `flutter_rust_net/test/network/dio_adapter_transfer_state_test.dart`

**Step 2: Run baseline targeted tests**

Run:

```bash
cd /Users/zyyziyunying/harrypet_flutter/flutter_rust_net && flutter test test/network/rhttp_adapter_test.dart test/network/request_body_channel_consistency_test.dart test/network/dio_adapter_transfer_state_test.dart
```

Expected: command runs and provides a concrete baseline for this task.
If failures appear, treat each failure as an explicit implementation gap list
for Step 3.

**Step 3: Write the minimal implementation**

Delete the bridge/runtime code and legacy tests, then fix any remaining imports
or references so the package compiles with only `RhttpAdapter` and `DioAdapter`
available. `test/network/network_smoke_flow_test.dart` must either be rewritten
to avoid direct `rust_adapter.dart` imports or removed.

**Step 4: Run tests to verify they pass**

Run:

```bash
cd /Users/zyyziyunying/harrypet_flutter/flutter_rust_net && flutter test test/network/rhttp_adapter_test.dart test/network/request_body_channel_consistency_test.dart test/network/dio_adapter_transfer_state_test.dart test/network/network_gateway/network_gateway_request_test.dart
```

Expected: PASS.

### Task 3: Remove benchmark/config legacy surfaces and update all benchmark callers

**Files:**
- Modify: `flutter_rust_net/lib/network/benchmark/benchmark_config.dart`
- Modify: `flutter_rust_net/lib/network/benchmark/benchmark_report.dart`
- Modify: `flutter_rust_net/lib/network/benchmark/benchmark_runner.dart`
- Modify: `flutter_rust_net/lib/network/benchmark/benchmark_enums.dart`
- Modify: `flutter_rust_net/test/network/benchmark_runner_test.dart`
- Modify: `flutter_rust_net/test/network/cache_channel_consistency_test.dart`
- Modify: `flutter_rust_net/test/network/benchmark_types_test.dart`
- Modify: `flutter_rust_net/test/network/network_realistic_flow_test.dart`
- Modify: `flutter_rust_net/tool/network_bench.dart`
- Modify: `flutter_rust_net/tool/p1_non_loopback_bench.dart`
- Modify: `flutter_rust_net/tool/p1_aggregate/p1_aggregate_io.dart`
- Modify: `flutter_rust_net/tool/p1_aggregate/p1_aggregate_models.dart`
- Modify: `flutter_rust_net/tool/p1_aggregate/p1_aggregate_render.dart`
- Delete: `flutter_rust_net/tool/_rust_tool_utils.dart`
- Modify: `flutter_rust_net/example/lib/apis/example_app_config.dart`
- Modify: `flutter_rust_net/example/lib/pages/benchmark_page.dart`

**Step 1: Run a legacy-surface baseline inventory**

Run:

```bash
cd /Users/zyyziyunying/harrypet_flutter/flutter_rust_net && rg -n "initializeRust|requireRust|rustMaxInFlightTasks|rustCache|rustAdapter:|_rust_tool_utils" lib/network/benchmark test/network/benchmark_runner_test.dart test/network/cache_channel_consistency_test.dart test/network/benchmark_types_test.dart test/network/network_realistic_flow_test.dart tool/network_bench.dart tool/p1_non_loopback_bench.dart tool/p1_aggregate example/lib/apis/example_app_config.dart example/lib/pages/benchmark_page.dart
cd /Users/zyyziyunying/harrypet_flutter/flutter_rust_net && rg -n "RustBridgeApi|rustBridgeApi|NetAdapter\\? rustAdapter" lib/network/benchmark/benchmark_runner.dart test/network/benchmark_runner_test.dart tool/network_bench.dart
```

Expected: matches exist before cleanup and define the explicit removal/edit
surface for this task.

**Step 2: Run baseline benchmark-focused tests**

Run:

```bash
cd /Users/zyyziyunying/harrypet_flutter/flutter_rust_net && flutter test test/network/benchmark_runner_test.dart test/network/cache_channel_consistency_test.dart test/network/benchmark_types_test.dart test/network/network_realistic_flow_test.dart
```

Expected: command runs and provides a concrete baseline for this task.
If failures appear, treat each failure as an explicit implementation gap list
for Step 3.

**Step 3: Write the minimal implementation**

Apply benchmark cleanup to both library surfaces and all callers:

- remove `runNetworkBenchmark(..., rustAdapter:)` parameter usage and update all
  direct callers/tests accordingly
- remove `initializeRust` / `requireRust` / `rustMaxInFlightTasks` /
  `rustCache*` benchmark fields and related report/config semantics
- keep `BenchmarkChannel.rust` only as a compatibility alias for the primary
  request channel; update tests/tooling copy to match that exact contract
- remove dead helper tooling (`tool/_rust_tool_utils.dart`) and any references
  to it

**Step 4: Run verification to confirm cleanup**

Run:

```bash
cd /Users/zyyziyunying/harrypet_flutter/flutter_rust_net && ! rg -n "initializeRust|requireRust|rustMaxInFlightTasks|rustCache|rustAdapter:|_rust_tool_utils" lib/network/benchmark test/network/benchmark_runner_test.dart test/network/cache_channel_consistency_test.dart test/network/benchmark_types_test.dart test/network/network_realistic_flow_test.dart tool/network_bench.dart tool/p1_non_loopback_bench.dart tool/p1_aggregate example/lib/apis/example_app_config.dart example/lib/pages/benchmark_page.dart
cd /Users/zyyziyunying/harrypet_flutter/flutter_rust_net && ! rg -n "RustBridgeApi|rustBridgeApi|NetAdapter\\? rustAdapter" lib/network/benchmark/benchmark_runner.dart test/network/benchmark_runner_test.dart tool/network_bench.dart
cd /Users/zyyziyunying/harrypet_flutter/flutter_rust_net && flutter test test/network/benchmark_runner_test.dart test/network/cache_channel_consistency_test.dart test/network/benchmark_types_test.dart test/network/network_realistic_flow_test.dart
```

Expected: the `rg` command returns no matches for removed legacy
fields/surfaces, including the benchmark API signature surface;
targeted benchmark-focused tests PASS.

### Task 4: Remove package dependency, tooling, native project, and example Rust wiring

**Files:**
- Modify: `flutter_rust_net/pubspec.yaml`
- Delete: `flutter_rust_net/flutter_rust_bridge.yaml`
- Delete: `flutter_rust_net/tool/rust_codegen.dart`
- Delete: `flutter_rust_net/tool/rust_build.dart`
- Delete: `flutter_rust_net/native/rust/net_engine/`
- Modify: `flutter_rust_net/example/android/app/build.gradle.kts`
- Modify: `flutter_rust_net/example/README.md`

**Step 1: Run baseline verification**

First prove stale dependency/build wiring still exists:

Run:

```bash
cd /Users/zyyziyunying/harrypet_flutter/flutter_rust_net && rg -n "flutter_rust_bridge|rust_codegen.dart|rust_build.dart|native/rust/net_engine|cargo ndk|net_engine" pubspec.yaml tool example/android/app/build.gradle.kts example/README.md
```

Expected: matches show the dependency and build wiring still present.

**Step 2: Run the package resolution check**

Run:

```bash
cd /Users/zyyziyunying/harrypet_flutter/flutter_rust_net && flutter pub get
```

Expected: PASS before cleanup, establishing a baseline.

**Step 3: Write the minimal implementation**

Remove:

- `flutter_rust_bridge` from `pubspec.yaml`
- FRB tool/config files
- package-local native Rust project
- example Android Rust build tasks and README references

Then run `flutter pub get` again so lock/resolution state reflects the new
dependency graph.

**Step 4: Run verification to confirm removal**

Run:

```bash
cd /Users/zyyziyunying/harrypet_flutter/flutter_rust_net && flutter pub get
cd /Users/zyyziyunying/harrypet_flutter/flutter_rust_net && ! rg -n "flutter_rust_bridge|rust_codegen.dart|rust_build.dart|native/rust/net_engine|cargo ndk|net_engine" pubspec.yaml tool example/android/app/build.gradle.kts example/README.md
cd /Users/zyyziyunying/harrypet_flutter/flutter_rust_net/example && flutter pub get
cd /Users/zyyziyunying/harrypet_flutter/flutter_rust_net/example && flutter build apk --debug
```

Expected:
- package and example `flutter pub get` PASS
- the `rg` command returns no relevant matches in the remaining files
- example APK debug build PASS (proves Rust Gradle wiring is not required anymore)

### Task 5: Update docs and workspace instructions to match the hard cut

**Files:**
- Modify: `flutter_rust_net/README.md`
- Modify: `flutter_rust_net/FLUTTER_RUST_NET_OVERVIEW_ZH.md`
- Modify: `flutter_rust_net/AGENTS.md`
- Modify: `AGENTS.md`
- Modify: `flutter_rust_net/docs/README.md`
- Modify or archive: `flutter_rust_net/docs/flutter_rust_network_layer_design.md`
- Modify: `flutter_rust_net/docs/problems/2026-04-02-project-progress-and-gap-assessment.md`
- Modify: `flutter_rust_net/docs/problems/2026-04-02-rhttp-thin-gateway-design-review-status-check.md`
- Modify: `flutter_rust_net/docs/progress/README.md`
- Modify: `flutter_rust_net/docs/progress/p1_status_2026-02-25.md`
- Modify: `flutter_rust_net/docs/progress/p2_status_2026-03-02.md`
- Modify: `flutter_rust_net/docs/progress/rust_lifecycle_scope_status_2026-03-12.md`
- Modify: `flutter_rust_net/docs/progress/real_device_test_commands_2026-03-02.md`
- Modify: `flutter_rust_net/docs/plan/2026-04-01-flutter-rust-net-rhttp-thin-gateway-design.md`
- Modify or archive:
  `flutter_rust_net/docs/plan/cache_namespace_budget_governance_plan_2026-03-14.md`
- Modify: `flutter_rust_net/docs/plan/README.md`
- Relabel/archive if still linked as current guidance:
  `flutter_rust_net/docs/dio_rust_test/*`

**Step 1: Run baseline verification**

Run:

```bash
cd /Users/zyyziyunying/harrypet_flutter && rg -n "flutter_rust_bridge|RustAdapter|standardWithRust|rust_build.dart|rust_codegen.dart|native/rust/net_engine|cargo test -q|initializeRust|requireRust|rustMaxInFlightTasks|rustCache" flutter_rust_net/README.md flutter_rust_net/FLUTTER_RUST_NET_OVERVIEW_ZH.md flutter_rust_net/AGENTS.md AGENTS.md flutter_rust_net/docs/README.md flutter_rust_net/docs/flutter_rust_network_layer_design.md flutter_rust_net/docs/problems/2026-04-02-project-progress-and-gap-assessment.md flutter_rust_net/docs/problems/2026-04-02-rhttp-thin-gateway-design-review-status-check.md flutter_rust_net/docs/progress/README.md flutter_rust_net/docs/progress/p1_status_2026-02-25.md flutter_rust_net/docs/progress/p2_status_2026-03-02.md flutter_rust_net/docs/progress/rust_lifecycle_scope_status_2026-03-12.md flutter_rust_net/docs/progress/real_device_test_commands_2026-03-02.md flutter_rust_net/docs/plan/2026-04-01-flutter-rust-net-rhttp-thin-gateway-design.md flutter_rust_net/docs/plan/cache_namespace_budget_governance_plan_2026-03-14.md flutter_rust_net/docs/plan/README.md
```

Expected: matches show the docs still describe the removed architecture.

**Step 2: Write the documentation changes**

Update docs so they consistently describe:

- a pure `rhttp + Dio` package
- no package-local Rust engine
- no FRB build/codegen/runtime workflow
- benchmark/docs contract decisions after hard cut
- current validation baseline as `flutter test`

Keep archived historical records untouched unless they remain linked from active
entry points.

**Step 3: Run active-doc verification**

Run:

```bash
cd /Users/zyyziyunying/harrypet_flutter && ! rg -n "flutter_rust_bridge|RustAdapter|standardWithRust|rust_build.dart|rust_codegen.dart|native/rust/net_engine|cargo test -q|initializeRust|requireRust|rustMaxInFlightTasks|rustCache" flutter_rust_net/README.md flutter_rust_net/FLUTTER_RUST_NET_OVERVIEW_ZH.md flutter_rust_net/AGENTS.md AGENTS.md flutter_rust_net/docs/README.md flutter_rust_net/docs/problems/2026-04-02-project-progress-and-gap-assessment.md flutter_rust_net/docs/problems/2026-04-02-rhttp-thin-gateway-design-review-status-check.md flutter_rust_net/docs/progress/README.md flutter_rust_net/docs/progress/p1_status_2026-02-25.md flutter_rust_net/docs/progress/p2_status_2026-03-02.md flutter_rust_net/docs/progress/rust_lifecycle_scope_status_2026-03-12.md flutter_rust_net/docs/progress/real_device_test_commands_2026-03-02.md flutter_rust_net/docs/plan/2026-04-01-flutter-rust-net-rhttp-thin-gateway-design.md flutter_rust_net/docs/plan/cache_namespace_budget_governance_plan_2026-03-14.md flutter_rust_net/docs/plan/README.md
cd /Users/zyyziyunying/harrypet_flutter && ! rg -n "docs/flutter_rust_network_layer_design.md|docs/dio_rust_test/" flutter_rust_net/docs/README.md flutter_rust_net/docs/plan/README.md flutter_rust_net/docs/progress/README.md
```

Expected: active entry-point docs contain no stale legacy current-state wording.
If `docs/flutter_rust_network_layer_design.md` or `docs/dio_rust_test/*` are
retained only as historical records, active entry-point docs must stop linking
to them as current guidance.

**Step 4: Run full verification**

Run:

```bash
cd /Users/zyyziyunying/harrypet_flutter/flutter_rust_net && flutter test
```

Expected: PASS.
