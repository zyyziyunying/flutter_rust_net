# flutter_rust_net `rhttp + Dio` Hard-Cut Design

> Date: 2026-04-02
> Status: Approved for implementation (revised on 2026-04-03 after review-findings alignment)
> Scope: remove `flutter_rust_bridge`, package-local `net_engine`, and all legacy Rust compatibility surfaces from `flutter_rust_net`

## 1. Background

`flutter_rust_net` has already completed the main thin-gateway V1 transition:

- request happy path: `RhttpAdapter`
- fallback path: `DioAdapter`
- transfer path: Dio-only

The remaining repository state is structurally split:

- the runtime request path is already `rhttp + Dio`
- the repository still ships `RustAdapter`, FRB generated bindings, Rust build/codegen tooling, package-local `native/rust/net_engine`, and related benchmark/cache/test/docs baggage

That split no longer creates product value for this repository. It only keeps
maintenance burden and misleading public/runtime concepts alive.

The selected direction is therefore a hard cut:

- `flutter_rust_net` becomes a pure Dart/Flutter thin gateway over `rhttp + Dio`
- all FRB and package-local Rust engine ownership are removed

## 2. Decision Summary

### Core decision

- Keep the package focused on:
  - unified request and transfer contracts
  - routing policy and controlled fallback
  - `rhttp` primary request execution
  - Dio fallback and Dio-only transfer execution
- Remove all legacy Rust bridge/runtime surfaces:
  - `RustAdapter`
  - `RustBridgeApi` / `FrbRustBridgeApi`
  - `RustEngineInitOptions`
  - `lib/rust_bridge/*`
  - `flutter_rust_bridge` package dependency
  - `flutter_rust_bridge.yaml`
  - `tool/rust_codegen.dart`
  - `tool/rust_build.dart`
  - `native/rust/net_engine`
- Remove public compatibility shims that still imply FRB ownership:
  - `BytesFirstNetworkClient.standardWithRust()`
  - `BytesFirstNetworkClient.rustAdapter`
  - benchmark `rustInitialized` compatibility getter

### Intentional temporary naming debt

This cleanup does not rename every legacy-compatible term in the same change.

The following remain temporarily preserved as compatibility names for the
current primary request channel:

- `NetChannel.rust`
- `NetFeatureFlag.enableRustChannel`

Their semantics after the hard cut are explicit:

- `NetChannel.rust` means the `rhttp` primary request channel
- `enableRustChannel` means "enable the primary native-backed request channel"

This keeps the cleanup focused on removing unused architecture first. A later
rename-only pass can change `rust` to `native` or `primary`.

## 3. Goals

- Remove the package dependency on `flutter_rust_bridge`.
- Remove all Dart-side runtime, test, and tooling dependence on package-local
  Rust code.
- Remove package-local Rust source, build wiring, and generated bindings from
  the repository.
- Keep the current business-facing request/transfer contracts stable where they
  still match the `rhttp + Dio` architecture.
- Make repository docs, examples, and benchmarks describe only the architecture
  that actually exists.

## 4. Non-Goals

- Do not rename `NetChannel.rust` and `enableRustChannel` in this change.
- Do not introduce new transport features while cleaning up legacy surfaces.
- Do not preserve FRB-only cache/runtime semantics as hidden compatibility
  behavior.
- Do not keep a no-op `RustAdapter` or other empty placeholder types.

## 5. Target Architecture After Cleanup

### Request path

```text
Business
  -> BytesFirstNetworkClient
  -> NetworkGateway
  -> RoutingPolicy
  -> RhttpAdapter
  -> DioAdapter (fallback only)
```

### Transfer path

```text
Business
  -> BytesFirstNetworkClient
  -> NetworkGateway
  -> DioAdapter only
```

### Ownership

- `BytesFirstNetworkClient`
  - package entry point
  - owns default `baseUrl`, bytes-first convenience helpers, and stable request
    ergonomics
- `NetworkGateway`
  - owns route selection and safe fallback behavior
- `RhttpAdapter`
  - owns primary request execution and request/response/error mapping
- `DioAdapter`
  - owns fallback request execution and all transfer-task execution

No package-local native lifecycle, codegen, or dynamic library loading remains.

## 6. Public API Strategy

### APIs to keep

- `NetRequest`
- `NetResponse`
- `NetTransferTaskRequest`
- `NetTransferEvent`
- `NetException`
- `NetFeatureFlag`
- `RoutingPolicy`
- `NetworkGateway`
- `BytesFirstNetworkClient.standard()`
- `BytesFirstNetworkClient.request()`
- `BytesFirstNetworkClient.requestRaw()`
- `BytesFirstNetworkClient.requestDecoded()`
- `RhttpAdapter`
- `DioAdapter`

### APIs to remove

- `RustAdapter`
- `RustEngineInitOptions`
- `normalizeRustEngineInitOptions(...)`
- `RustBridgeApi`
- `FrbRustBridgeApi`
- `BytesFirstNetworkClient.standardWithRust()`
- `BytesFirstNetworkClient.rustAdapter`
- `runNetworkBenchmark(..., rustAdapter: ...)` parameter surface
- all `rust_bridge` generated/public types

### Explicit `rust*` compatibility matrix

- `BytesFirstNetworkClient.standard({ rustAdapter })`:
  keep in this cut as a compatibility injection point, but treat the parameter
  as "primary request adapter injection", not as a legacy engine initializer.
  Rename-only follow-up: `rustAdapter` -> `primaryAdapter`.
- `NetworkGateway.rustAdapter`:
  keep in this cut as constructor compatibility naming debt.
  Rename-only follow-up aligned with `NetChannel.rust` rename.
- `runNetworkBenchmark(..., rustAdapter:)`:
  remove in this cut. Benchmark entry points should not expose legacy
  Rust-shaped adapter naming after hard cut.
- `BenchmarkChannel.rust`:
  keep in this cut as a compatibility alias for the primary request channel.
  Rename-only follow-up with `NetChannel.rust` cleanup.

### Behavioral rules that remain

- `standard()` stays the safe constructor that defaults to Dio unless
  `featureFlag.enableRustChannel == true`.
- `forceChannel: NetChannel.rust` still routes requests to the primary request
  adapter.
- `forceChannel: NetChannel.rust` for transfer APIs still fails explicitly.
- fallback remains limited by the existing error and idempotency rules.
- request bodies continue to use one shared bytes-first encoding contract.

## 7. Benchmark And Cache Strategy

The benchmark layer must stop implying retained FRB/cache value that no longer
belongs to the package direction.

Required changes:

- remove all benchmark dependence on `RustBridgeApi`
- remove `RustEngineInitOptions`-based benchmark config shaping
- remove benchmark API/caller surfaces that still expose
  `runNetworkBenchmark(..., rustAdapter:)`
- remove compatibility getters/fields whose only meaning was legacy bridge
  initialization state
- keep benchmark scenarios that still exercise:
  - `rhttp` request path
  - Dio fallback behavior
  - Dio transfer behavior where relevant
- remove messaging that says Rust cache settings are ignored in V1; after the
  hard cut those settings should no longer exist in the benchmark-facing config

This explicitly abandons the old package-local Rust cache line instead of
pretending it still matters to the active architecture.

## 8. File-Level Removal Scope

### Dart/runtime removal

- `lib/network/rust_adapter.dart`
- `lib/network/rust_bridge_api.dart`
- `lib/network/rust_adapter/`
- `lib/rust_bridge/`

### Tests to remove or rewrite

- `test/network/rust_adapter/`
- `test/network/rust_adapter_lifecycle_test.dart`
- `test/network/rust_adapter_real_bridge_test.dart`
- `test/network/rust_adapter_shared_scope_test.dart`
- `test/network/rust_bridge_api_test.dart`
- `test/flutter_rust_net_test.dart`
- `test/network/network_smoke_flow_test.dart`
- `test/network/network_realistic_flow_test.dart`
- any benchmark/cache tests that depend on legacy Rust init/cache semantics

### Tooling and config to remove

- `flutter_rust_bridge.yaml`
- `tool/rust_codegen.dart`
- `tool/rust_build.dart`
- `tool/_rust_tool_utils.dart`
- benchmark/example CLI and aggregation callers that still expose removed
  legacy benchmark fields (`initializeRust`, `requireRust`,
  `rustMaxInFlightTasks`, `rustCache*`)
- helper tooling that only exists for the removed Rust pipeline

### Native/example removal

- `native/rust/net_engine/`
- example Android Gradle wiring that builds `net_engine`
- example README text that claims local Rust build integration
- example benchmark presets/UI copy that still describe legacy benchmark knobs

## 9. Documentation Strategy

Update repository-facing docs so they tell one story only:

- this package is a thin gateway over `rhttp + Dio`
- there is no package-local Rust engine ownership anymore
- there is no FRB setup/build/codegen step anymore

Priority docs to update:

- `README.md`
- `FLUTTER_RUST_NET_OVERVIEW_ZH.md`
- `flutter_rust_net/AGENTS.md`
- workspace `../AGENTS.md`
- `docs/README.md`
- `docs/progress/README.md`
- `docs/progress/archive/p2_status_2026-03-02.md`
- `docs/plan/archive/cache_namespace_budget_governance_plan_2026-03-14.md`
- relevant active `docs/problems/` and `docs/progress/` records when they are
  still presented as current state

Archived records can remain historical unless they actively mislead current
entry points.

## 10. Testing Strategy

Keep and strengthen tests that validate the surviving contract:

- routing policy
- request routing to `RhttpAdapter`
- fallback from primary request path to Dio
- transfer Dio-only behavior
- request body encoding/channel consistency
- bytes-first client behavior
- benchmark behavior that still matches the active architecture

Remove tests whose subject no longer exists:

- Rust engine init/lifecycle
- FRB loading
- real bridge execution
- legacy Rust cache-only semantics

Validation target after cleanup:

- `flutter pub get`
- `flutter test`

No Rust validation lane remains.

## 11. Risks And Mitigations

### Risk 1: benchmark/config drift

The benchmark layer still carries several legacy Rust concepts. This is the
most likely place for stale fields or misleading report text to survive.

Mitigation:

- treat benchmark cleanup as a first-class scope item, not a follow-up
- remove unsupported fields instead of silently ignoring them
- include verification gates that explicitly cover benchmark API signature
  removal (`NetAdapter? rustAdapter`, `rustBridgeApi` / `RustBridgeApi`), not
  only `rustAdapter:` call-site syntax

### Risk 2: stale example/native build wiring

The example Android app still references `native/rust/net_engine`.

Mitigation:

- remove Gradle Rust build tasks in the same change as native directory removal
- update example README and usage flow at the same time
- validate with example-level commands (`cd example && flutter pub get`) plus
  one executable build/run path (for Android use `flutter build apk --debug`)
  instead of text grep only

### Risk 3: mixed naming after the cut

`NetChannel.rust` and `enableRustChannel` will still look legacy even after the
bridge is gone.

Mitigation:

- document the semantics clearly in README and overview
- defer rename-only cleanup to a dedicated, smaller follow-up

## 12. Acceptance Criteria

The hard cut is complete when all of the following are true:

- `pubspec.yaml` no longer depends on `flutter_rust_bridge`
- no Dart library exports or runtime paths reference FRB or `RustAdapter`
- the repository no longer contains package-local `native/rust/net_engine`
- the example no longer builds or references package-local Rust libraries
- active docs entry points (including `docs/README.md`,
  `docs/progress/README.md`, `docs/progress/archive/p2_status_2026-03-02.md`, and
  `docs/plan/archive/cache_namespace_budget_governance_plan_2026-03-14.md`) no longer
  describe removed Rust ownership as current state
- docs describe only `rhttp + Dio`
- `flutter test` passes
