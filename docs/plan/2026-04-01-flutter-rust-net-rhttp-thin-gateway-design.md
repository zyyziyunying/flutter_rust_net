# flutter_rust_net `rhttp + Dio` Thin Gateway Design

> Date: 2026-04-01
> Status: Draft approved for design direction

## 1. Background

`flutter_rust_net` today mixes two different concerns:

1. A useful gateway layer:
   - unified `NetRequest` / `NetResponse`
   - `forceChannel` routing
   - controlled fallback from the Rust-backed path to Dio
   - migration-time guardrails
2. A costly self-maintained transport stack:
   - `RustAdapter`
   - `flutter_rust_bridge`
   - package-local `native/rust/net_engine`
   - codegen, build, lifecycle, and benchmark maintenance burden

The practical value is mostly in the first part, not the second.

The new direction is therefore:

- keep a thin `NetworkGateway`
- replace the self-maintained Rust request engine with `rhttp`
- keep `Dio` as the fallback and migration control channel
- stop treating `flutter_rust_net` as a general-purpose self-built Rust HTTP engine

## 2. Decision Summary

The selected direction is **Option B: thin gateway V1**.

### Core decision

- Keep `NetRequest`, `NetResponse`, `NetException`, `NetworkGateway`, and `BytesFirstNetworkClient`.
- Replace the current request-path `RustAdapter` implementation with a new `RhttpAdapter` that implements `NetAdapter`.
- Keep `DioAdapter` as the control and fallback path.
- Limit phase 1 to the regular `request()` path.
- Keep transfer tasks on Dio in phase 1 and do not attempt a same-round transfer migration.

### Product framing after the change

After this migration, `flutter_rust_net` is no longer "our own Rust engine plus Flutter bridge".
It becomes a **thin migration and traffic-governance layer over `rhttp + Dio`**.

## 3. Goals

- Remove request-path dependence on `flutter_rust_bridge` and package-local `net_engine`.
- Preserve a small and stable business-facing request contract.
- Preserve migration guardrails:
  - force routing
  - controlled fallback
  - deterministic behavior under rollout
- Reduce maintenance cost for native build, lifecycle, and codegen.
- Keep the request path easy to reason about and test.

## 4. Non-Goals

- Do not preserve the current self-managed Rust lifecycle model as a first-class feature.
- Do not migrate upload/download task orchestration in phase 1.
- Do not keep every `net_engine`-specific tuning knob if it only existed to support the old engine.
- Do not position this package as a full competitor to mature HTTP clients.

## 5. Proposed Architecture

### Request path

```text
Business
  -> BytesFirstNetworkClient
  -> NetworkGateway
  -> RoutingPolicy
  -> DioAdapter | RhttpAdapter
```

### Roles

- `BytesFirstNetworkClient`
  - stays as the entry point used by business code
  - continues to own `baseUrl` defaults and bytes-first decoding helpers
- `NetworkGateway`
  - stays intentionally thin
  - only decides route, applies fallback rules, and records route metadata
- `DioAdapter`
  - remains the fallback and compatibility path
  - remains the transfer-task implementation in phase 1
- `RhttpAdapter`
  - becomes the primary Rust-backed request adapter
  - owns request execution and response/error mapping into existing net models

### What gets removed from the request path

- `flutter_rust_bridge` request dependency
- package-local `native/rust/net_engine` request execution
- Rust bridge loading and lifecycle synchronization for normal requests
- request-path codegen/build steps tied to the old engine

## 6. Public API Strategy

### APIs to keep

- `NetRequest`
- `NetResponse`
- `NetException`
- `NetFeatureFlag`
- `RoutingPolicy`
- `NetworkGateway`
- `BytesFirstNetworkClient.request()`
- `BytesFirstNetworkClient.requestRaw()`
- `BytesFirstNetworkClient.requestDecoded()`

### Compatibility choices

- Keep `NetChannel.dio` and `NetChannel.rust` in V1.
  - `NetChannel.rust` now means "the primary Rust-backed/native request channel", implemented by `rhttp`.
  - This avoids a large business-side rename during the migration.
- Keep `forceChannel`.
- Keep `enableRustChannel` in V1 as a compatibility flag name.
  - Semantically it now means "enable the `rhttp` primary channel".
  - A later cleanup can rename it to something less misleading, such as `enablePrimaryChannel` or `enableNativeChannel`.

### APIs to de-emphasize or retire

- `RustAdapter.initializeEngine()` / `shutdownEngine()`
- `RustEngineInitOptions`
- FRB request bridge types and request-path docs
- `expectLargeResponse` as a transport-specific optimization knob
  - preserve for compatibility in V1 if needed
  - treat as a no-op unless a real `rhttp`-level optimization is wired behind it

### Convenience constructors

- Keep `BytesFirstNetworkClient.standard()` as the safe default that stays on Dio.
- Keep `BytesFirstNetworkClient.standardWithRust()` in V1 as a compatibility convenience, but make it build a client with `RhttpAdapter`, not the old self-managed Rust engine.
- Document clearly that explicit engine initialization is no longer required for the request path.

## 7. Routing and Fallback Rules

### Routing

V1 routing should remain intentionally small:

1. If `forceChannel` is set, obey it.
2. If `enableRustChannel == false`, route to Dio.
3. Otherwise, route to `RhttpAdapter`.

No interface classification, payload-size routing, or network-profile routing is introduced in V1.
Those are valid later improvements, but they are not needed to justify this migration.

### Fallback

Keep the current fallback philosophy:

- fallback only from the Rust-backed primary path to Dio
- fallback only when the error is eligible:
  - `timeout`
  - `dns`
  - `tls`
  - `io`
  - `infrastructure`
- fallback only when the request is safe:
  - idempotent HTTP method, or
  - explicit `Idempotency-Key`

This keeps the existing migration guardrail value and avoids changing business risk posture while the transport implementation changes underneath.

### Readiness model

The current `rustAdapter.isReady` gate exists mainly because the old path depends on manual engine initialization and shared lifecycle state.

For V1:

- `RhttpAdapter.isReady` should be effectively always `true` after construction.
- the request path no longer relies on explicit engine initialization
- the gateway readiness fallback branch becomes structurally simpler

## 8. Transfer Task Guardrail for V1

Phase 1 does **not** migrate transfer orchestration.

### Decision

- `startTransferTask()`, `pollTransferEvents()`, and `cancelTransferTask()` remain Dio-backed in V1.
- `NetworkGateway` continues to expose those methods so business call sites do not need to change.

### Guardrail behavior

- default transfer behavior remains Dio-only
- if a caller explicitly forces `NetChannel.dio`, honor it
- if a caller explicitly forces `NetChannel.rust` for transfer operations in V1, fail explicitly instead of silently rerouting

Explicit failure is preferred here because it prevents hidden behavior drift during migration.
If a caller asks for the Rust-backed transfer path, the gateway should not pretend the request used that path when it did not.

## 9. Testing Strategy

### Must-have request coverage

- `RhttpAdapter` request success mapping
- `RhttpAdapter` error mapping into existing `NetErrorCode`
- `NetworkGateway` route-to-`rhttp` behavior
- `NetworkGateway` fallback from `rhttp` to Dio
- idempotency and `Idempotency-Key` fallback safety
- `BytesFirstNetworkClient` compatibility on:
  - `baseUrl`
  - body encoding
  - bytes-first decode helpers
  - `forceChannel`

### Transfer coverage for V1

- transfer APIs still work on Dio
- forcing Rust for transfer returns the expected deterministic failure
- no silent route drift for transfer tasks

### Validation scope

- run `cd flutter_rust_net && flutter test`
- do not run `flutter analyze` by default
- update request-path docs when behavior or terminology changes

## 10. Documentation Changes

The following docs should be updated as part of the migration:

- `flutter_rust_net/README.md`
- `flutter_rust_net/FLUTTER_RUST_NET_OVERVIEW_ZH.md`
- `flutter_rust_net/docs/analyse/rust_network_business_fit_analysis_2026-03-13.md`
- benchmark/runbook docs that currently describe Dio vs self-managed Rust engine

The updated wording should consistently describe the package as:

- a thin gateway
- `rhttp` primary request path
- Dio fallback path
- Dio-only transfer path in V1

## 11. Impacted Code Areas

Expected primary touch points:

- `flutter_rust_net/lib/network/net_adapter.dart`
- `flutter_rust_net/lib/network/network_gateway.dart`
- `flutter_rust_net/lib/network/bytes_first_network_client.dart`
- `flutter_rust_net/lib/network/net_feature_flag.dart`
- `flutter_rust_net/lib/network/net_models.dart`
- `flutter_rust_net/lib/network/dio_adapter.dart`
- new: `flutter_rust_net/lib/network/rhttp_adapter.dart`
- request-path tests under `flutter_rust_net/test/network/`
- package docs and example text

Expected removals or deprecations:

- request-path use of `flutter_rust_net/lib/network/rust_adapter.dart`
- request-path use of `flutter_rust_net/lib/network/rust_bridge_api.dart`
- request-path README and benchmark references that assume package-local `net_engine`

## 12. Risks and Mitigations

### Risk: naming confusion

`NetChannel.rust` and `enableRustChannel` become compatibility names even though the old custom engine is gone.

Mitigation:

- document this explicitly in README and API docs
- treat it as a deliberate V1 migration compatibility trade-off
- schedule a later naming cleanup only after behavior is stable

### Risk: transfer/request capability asymmetry

Requests will use `rhttp`, while transfer tasks remain on Dio.

Mitigation:

- make the split explicit in docs
- fail explicitly on forced Rust transfer requests
- keep phase 1 narrow instead of hiding mixed semantics

### Risk: benchmark continuity

Existing docs and tools describe Dio vs self-managed Rust engine.

Mitigation:

- rewrite benchmark framing to Dio vs `rhttp`
- avoid overclaiming continuity across the engine swap
- keep old benchmark docs archived as historical evidence, not current truth

### Risk: hidden adapter mismatch

Error mapping and body semantics may differ subtly between Dio and `rhttp`.

Mitigation:

- keep model-level tests behavior-focused
- add channel-consistency tests for request body encoding and error translation
- keep fallback behavior deterministic and narrow

## 13. Migration Phases

### Phase 1: request-path replacement

- add `rhttp` dependency
- add `RhttpAdapter`
- switch gateway request routing from old `RustAdapter` to `RhttpAdapter`
- preserve thin gateway and fallback logic
- keep transfer tasks Dio-only

### Phase 2: cleanup

- remove request-path FRB/native-engine assumptions from docs and APIs
- deprecate or remove old lifecycle/config types that only served the old engine
- simplify tests and tooling tied only to the old request engine

### Phase 3: optional follow-up

- decide whether transfer tasks need a separate `rhttp`-backed implementation
- if not needed, keep them permanently Dio-only and document that as the package contract

## 14. Final Position

This design intentionally narrows the package.

The package should keep only the part that is still strategically useful:

- migration guardrails
- explicit route control
- fallback safety
- stable business-facing request contracts

It should stop owning the part that mature libraries already solve better:

- the self-built Rust request engine
- request lifecycle orchestration for that engine
- request-path native codegen and packaging burden
