# `rhttp + Dio` Thin Gateway Design Review Problems

> Date: 2026-04-01
> Reviewed doc: `flutter_rust_net/docs/plan/2026-04-01-flutter-rust-net-rhttp-thin-gateway-design.md`

## Critical Findings

### 1. `standardWithRust()` compatibility is underspecified and likely not source-compatible

The design says Phase 1 should keep `BytesFirstNetworkClient.standardWithRust()` as a compatibility convenience, but change it to build a client with `RhttpAdapter`.

That is not source-compatible with the current public API surface unless V1 also ships a `RustAdapter`-shaped compatibility shim.

Current code still hard-codes `RustAdapter` in public factories and getters:

- `lib/network/bytes_first_network_client.dart`
  - `BytesFirstNetworkClient.standard(...)`
  - `BytesFirstNetworkClient.standardWithRust(...)`
  - `BytesFirstNetworkClient.rustAdapter`
- `lib/flutter_rust_net.dart`
  - still exports `network/rust_adapter.dart`

Current tests also assert `RustAdapter`-specific behavior:

- `test/network/bytes_first_network_client_test.dart`

If the implementation simply swaps in `RhttpAdapter`, this is not just an internal refactor. It changes API shape and invalidates current call sites and tests.

### 2. Request-body semantics will drift unless `RhttpAdapter` is constrained to the existing raw-bytes contract

Today the package enforces one shared byte-level request encoding contract across Dio and Rust:

- `bodyBytes`: raw bytes
- `String`: UTF-8 bytes
- other JSON-encodable values: UTF-8 JSON bytes
- no automatic `content-type` rewrite

That contract is implemented in:

- `lib/network/request_body_codec.dart`

It is documented in:

- `README.md`

It is validated by parity tests:

- `test/network/request_body_channel_consistency_test.dart`

If `RhttpAdapter` uses `rhttp` convenience helpers for JSON/form bodies instead of feeding the already-encoded bytes through the existing codec, channel semantics will drift immediately:

- auto-added headers may differ
- payload encoding may differ
- fallback parity guarantees become weaker

Phase 1 should explicitly require `RhttpAdapter` to reuse the existing body encoding contract instead of adopting `rhttp` sugar APIs.

### 3. The readiness/lifecycle section overclaims what disappears

The design states that request-path FRB/init complexity goes away and `RhttpAdapter.isReady` is effectively always true.

That is directionally fine, but the current abstraction still bakes lifecycle assumptions into multiple public and semi-public surfaces:

- `lib/network/net_adapter.dart`
  - has `isReady`
- `lib/network/bytes_first_network_client.dart`
  - factory logic assumes ready-vs-not-ready behavior
  - `standardWithRust()` exists specifically to initialize before use
- `example/lib/pages/request_lab_page.dart`
  - manually initializes Rust before sending requests
- `lib/network/benchmark/benchmark_runner.dart`
  - owns init/shutdown flow

If `rhttp` still needs any explicit init, client reuse, or disposal discipline, then the design is hiding lifecycle work rather than removing it.

Before implementation starts, the design should state one concrete ownership model:

- fully internalized lifecycle with no public init/dispose API, or
- explicit request-channel client lifecycle retained in a renamed public abstraction

### 4. Phase 1 is narrow in prose, but the impacted surface area is broader than the design currently admits

The doc positions Phase 1 as a request-only migration, but the current package surface still assumes Rust-engine behavior in adjacent tooling and docs:

- benchmark flow
  - `lib/network/benchmark/benchmark_runner.dart`
  - `lib/network/benchmark/benchmark_config.dart`
- example app request lab
  - `example/lib/pages/request_lab_page.dart`
- cache consistency tests
  - `test/network/cache_channel_consistency_test.dart`
- package exports
  - `lib/flutter_rust_net.dart`
- README / overview wording
  - `README.md`
  - `FLUTTER_RUST_NET_OVERVIEW_ZH.md`

If these are intentionally out of Phase 1, the design should say so explicitly and mark them as deferred cleanup. Otherwise they become hidden blockers during implementation.

## Follow-up Review Findings (2026-04-02)

### 5. `RhttpAdapter.isReady == true` hides runtime initialization failure behind the request path

Severity: Medium

The current implementation makes `RhttpAdapter.isReady` unconditionally return `true`, but the real native work still happens lazily on first request:

- `lib/network/rhttp_adapter.dart`
  - `_ensureInitialized()`
  - `_createClient()`
  - `_ensureClient()`

That changes the operational meaning of readiness compared with the current gateway contract:

- `lib/network/network_gateway.dart`
  - `request()` still uses `rustAdapter.isReady` to decide whether to short-circuit to Dio before touching the primary adapter

With the new adapter shape, native library load or client creation failures are no longer represented as “not ready” at routing time. They surface only after the request has already been routed into the primary path.

That creates a contract drift:

- `forceChannel: NetChannel.rust` requests lose the old “not ready -> direct Dio route” behavior
- non-idempotent requests that are not fallback-safe can now fail at runtime instead of taking the previous readiness bypass
- the design claim that request-path readiness is “effectively always true” becomes true only in the happy path, not as an operational guarantee

Phase 1 should either:

- narrow the readiness claim explicitly to “no public manual init API, but runtime initialization may still fail on first use”, or
- restore an explicit readiness / availability model for the new primary adapter instead of treating first-use initialization as equivalent to readiness

Status (2026-04-02): Resolved in V1 implementation.

- `RhttpAdapter.isReady` now reflects real request-path availability instead of returning `true` unconditionally.
- `NetworkGateway.request()` now performs an `RhttpAdapter` request-readiness preflight before routing into the primary request path.
- First-use native init / client-create failures are now treated as “rust not ready” at routing time, so `forceChannel: NetChannel.rust` preserves the previous direct-to-Dio bypass semantics instead of being mislabeled as ready and only failing after dispatch.

### 6. The injected request-handler seam weakens confidence in production-path parity

Severity: Low

The new `RhttpAdapter` tests rely on an injected request-handler seam because `flutter test` cannot currently load the native `rhttp` library:

- `lib/network/rhttp_adapter.dart`
  - `RhttpAdapterRequestHandler`
  - `_requestHandler`
- `test/network/rhttp_adapter_test.dart`
- `test/network/request_body_channel_consistency_test.dart`

This seam is useful for unit testing adapter mapping logic, but it currently short-circuits the most important production-path behaviors:

- whether `ClientSettings(throwOnStatusCode: false)` is actually honored by real `rhttp`
- whether real `rhttp` preserves the no-sugar body/header contract without silently rewriting `content-type`
- whether lazy init and client reuse behave safely under real native loading

The risk is not that the seam is inherently wrong. The risk is that the current test suite now proves “pre-dispatch request object shaping” more strongly than “real transport parity”.

This is especially visible in the updated parity test:

- `test/network/request_body_channel_consistency_test.dart`
  - it no longer exercises a real primary-path fallback chain
  - it now compares Dio’s on-wire request with the seam-captured request object that would be sent to `rhttp`

Phase 1 should keep the seam if needed, but it should also document the limitation and pair it with at least one higher-fidelity acceptance strategy:

- targeted integration coverage outside plain `flutter test`
- manual/device validation for real `rhttp` request execution
- or an explicitly documented statement that request-path transport parity is only partially covered until native-capable tests are added

Status (2026-04-02): Partially resolved with explicit higher-fidelity coverage.

- The seam remains for fast unit coverage of adapter mapping and gateway behavior.
- `test/network/rhttp_adapter_test.dart` now adds native-capable real-`rhttp` checks for:
  - `ClientSettings(throwOnStatusCode: false)` effective behavior on real 4xx responses
  - lazy init readiness transition
  - client-create failure recovery and client reuse after success
- `test/network/request_body_channel_consistency_test.dart` now keeps the seam-based parity checks and adds native-capable on-wire parity checks for:
  - `encodeRequestBody()` contract reuse
  - no implicit `content-type` rewrite
- Because plain `flutter test` in this package still cannot load the `rhttp` native library by default, the real-path tests are opt-in and require `FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR` to point at a built `librhttp.dylib`.

## Open Questions / Assumptions

### 1. Is request-side cache behavior part of V1 compatibility?

`NetResponse` still exposes:

- `fromCache`
- `bodyFilePath`

Current behavior and tests assume the Rust-backed path can expose different cache/materialization metadata:

- `lib/network/net_models.dart`
- `test/network/cache_channel_consistency_test.dart`

The design does not say whether the new primary path must preserve cache-visible behavior, or whether these fields become best-effort / always-false in V1.

This needs an explicit decision before coding.

### 2. Is large-response file materialization still part of the retained contract?

Current public API still exposes:

- `NetRequest.expectLargeResponse`
- `NetResponse.bodyFilePath`
- `BytesFirstNetworkClient` file materialization and cleanup logic

Relevant files:

- `lib/network/net_models.dart`
- `lib/network/bytes_first_network_client.dart`

The design currently says `expectLargeResponse` can become a no-op, but does not say whether `bodyFilePath` remains meaningful on the new primary path.

If the new primary path is bytes-only in V1, that should be written down as an intentional behavior change.

### 3. Are benchmark and example flows in or out of Phase 1 acceptance?

The codebase currently has first-class benchmark and manual validation flows wired around Rust-engine lifecycle:

- `lib/network/benchmark/benchmark_runner.dart`
- `example/lib/pages/request_lab_page.dart`

The design mentions benchmark/doc rewriting, but not whether those flows must remain runnable in the same phase.

### 4. Is the goal “remove request-path dependence on FRB” meant literally or “remove direct package-owned FRB/native-engine maintenance”?

That wording matters.

If `rhttp` is used as an external dependency and still uses Rust/native integration internally, then the real architectural win is:

- stop owning package-local request-path FRB codegen
- stop owning package-local `net_engine`
- stop exposing self-managed engine lifecycle as a core package feature

That is a solid goal, but it is narrower than “remove dependence on FRB” in the absolute sense.

## Recommended Scope Cuts / API Simplifications

### 1. Keep only the request contract in the Phase 1 compatibility promise

Strong candidates to keep:

- `NetRequest`
- `NetResponse`
- `NetException`
- `NetworkGateway.request(...)`
- `BytesFirstNetworkClient.request*`
- `forceChannel`
- `NetChannel.dio`
- `NetChannel.rust` as a temporary compatibility name

Strong candidates to remove from the Phase 1 compatibility promise unless a shim is intentionally provided:

- `BytesFirstNetworkClient.standardWithRust()`
- `BytesFirstNetworkClient.rustAdapter`
- `RustEngineInitOptions`
- Rust-engine lifecycle APIs as supported request-path setup

### 2. Make transfer behavior truly Dio-only in Phase 1

The current gateway still contains substantial transfer routing, fallback, polling, and cancel-tracking logic.

Relevant file:

- `lib/network/network_gateway.dart`

If Phase 1 is supposed to be request-only, the simplest and clearest behavior is:

- transfer start uses Dio only
- transfer poll uses Dio only
- transfer cancel uses Dio only
- forcing `NetChannel.rust` on transfer fails deterministically with an explicit unsupported error

That keeps the gateway thinner and avoids mixed request/transfer semantics.

### 3. Add a compatibility matrix before implementation starts

The design should explicitly classify the following as one of:

- preserved
- preserved but renamed later
- preserved as no-op / best-effort
- deprecated in V1
- removed in V2

Suggested matrix entries:

- `standardWithRust`
- `rustAdapter` getter
- `enableRustChannel`
- `NetChannel.rust`
- `expectLargeResponse`
- `fromCache`
- `bodyFilePath`
- transfer `forceChannel`

### 4. Add contract tests before adapter implementation starts

Minimum must-have tests before shipping:

- request body parity between primary path and Dio fallback
- header parity for auto-inference-sensitive cases
- fallback eligibility parity by error type
- retained `NetResponse` metadata behavior
  - `requestId`
  - `fromCache`
  - `bodyFilePath`
  - `routeReason`
  - `fallbackReason`
- deterministic failure when transfer forces `NetChannel.rust`

Without those tests, the migration may look thin in structure while still drifting in behavior.
