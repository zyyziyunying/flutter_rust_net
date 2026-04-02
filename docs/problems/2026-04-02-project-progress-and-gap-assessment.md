# Current Project Progress And Gap Assessment

> Date: 2026-04-02
> Scope: `flutter_rust_net` current project status, main progress, and major gaps
> Basis:
> - current code / docs inspection
> - `flutter test`
> - `cd native/rust/net_engine && cargo test -q`

## Verdict

`flutter_rust_net` is no longer in an early prototype state. The project has
entered a thin-gateway V1 closing phase:

- the main request path has been switched to `rhttp + Dio`
- the legacy Rust bridge has been reduced to a retained compatibility/testing
  surface
- package-level Dart and Rust tests are currently green

But the project is still not at a clean “business app admission completed”
state. The remaining work is no longer primarily feature implementation. The
main gaps are:

- non-loopback / device / weak-network admission evidence is still incomplete
- high-fidelity native-path verification is still opt-in instead of default
- a significant part of the previous P2 Rust cache investment now sits mostly
  on the legacy bridge path rather than the current V1 happy path

## Current Progress

### 1. Thin-gateway V1 architecture is in place

The current architecture has been clarified and reflected consistently in code
and docs:

- request happy path: `RhttpAdapter`
- fallback path: `DioAdapter`
- transfer path: Dio-only in V1
- legacy `RustAdapter` / FRB / `native/rust/net_engine`: retained for
  compatibility and testing, not required by the normal V1 request path

Evidence:

- `README.md`
- `FLUTTER_RUST_NET_OVERVIEW_ZH.md`
- `lib/network/network_gateway.dart`
- `lib/network/bytes_first_network_client.dart`

### 2. P1 main engineering chain is mostly closed

According to the current P1 status document, the core engineering chain is
already considered mostly closed. The work focus has shifted from
implementation patching to admission evidence accumulation and a small amount
of review follow-up closing.

Already completed in the P1 fact source:

- routing baseline and benchmark aggregation are in place
- transfer upload/download semantics and fallback safety boundaries are aligned
- Rust config effectiveness path is connected
- public API has been made more conservative
- lifecycle risks were repaired
- one public remote smoke check has been archived

Current P1 work still in progress:

- Android / iOS / Wi-Fi / 4G / weak-network supplementary validation
- Rust config effectiveness evidence under real network conditions
- final “before business app integration” admission conclusion

Evidence:

- `docs/progress/p1_status_2026-02-25.md`

### 3. P2 cache capability is materially implemented

The Rust cache line is not just partially started. The current P2 fact source
shows that the following are already implemented:

- usable `DiskCache`
- TTL / ETag / Last-Modified revalidation
- namespace governance
- namespace budget
- root budget
- benchmark cache observation fields
- Dart init-option passthrough
- real Rust FFI cache-on/cache-off regression coverage

This means P2 has substantial implementation depth and test investment.

Evidence:

- `docs/progress/p2_status_2026-03-02.md`

### 4. The repository is currently in a healthy tested state

Fresh verification completed in the current environment:

- `flutter test` passed
- `cd native/rust/net_engine && cargo test -q` passed with `40 passed; 0 failed`

This indicates the current branch is not blocked by obvious red tests.

## Main Gaps And Defects

### 1. Business admission is still not closed

This is the highest-value gap.

The current P1 fact source still says the final business-access admission
conclusion has not been produced. The open work is not cosmetic:

- real-device samples are still being supplemented
- Wi-Fi / 4G / weak-network coverage is still missing from the final record
- public-network and device evidence still needs to be consolidated into a
  formal go / no-go conclusion

Impact:

- the project can be described as “engineering-ready in the local/test sense”
- it cannot yet be described as “business integration admission completed”

### 2. High-fidelity native-path verification is not part of the default test path

This is the most important verification limitation.

The default `flutter test` run is green, but several higher-fidelity test
groups are still skipped unless local native prerequisites are prepared:

- real `rhttp` tests require
  `FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR` and `librhttp.dylib`
- real bridge tests require a locally built `native/rust/net_engine` library

Impact:

- the default test lane strongly validates seam-backed behavior, gateway logic,
  request shaping, and package-level contracts
- it does not fully prove that the real native request path was exercised in a
  default environment

Evidence:

- `test/network/rhttp_adapter_test.dart`
- `test/network/request_body_channel_consistency_test.dart`
- `test/network/rust_adapter_real_bridge_test.dart`

### 3. P2 cache investment and V1 happy path are now partially misaligned

This is the largest structural mismatch in the current repository direction.

The current V1 request happy path uses `rhttp`, while the benchmark runner now
explicitly says Rust cache settings are ignored for the V1 `rhttp` request
path.

That means:

- a large amount of P2 cache work is real and valuable
- but much of that value currently sits on the retained legacy Rust bridge /
  `net_engine` line, not on the default V1 request path

Impact:

- the project has completed real cache engineering work
- but the direct business value of that work on the current default path is
  weaker than the raw implementation volume may suggest

Evidence:

- `lib/network/benchmark/benchmark_runner.dart`
- `docs/progress/p2_status_2026-03-02.md`
- `README.md`

### 4. API naming and compatibility debt is still visible

The thin-gateway V1 runtime model has already changed, but several public terms
still preserve legacy naming:

- `enableRustChannel`
- `NetChannel.rust`
- `standardWithRust()`
- deprecated `rustInitialized` compatibility getter on benchmark reports

This is currently manageable, but it continues to create cognitive overhead and
can mislead consumers into assuming the V1 happy path still maps directly to
the old self-managed Rust engine model.

Evidence:

- `lib/network/bytes_first_network_client.dart`
- `lib/network/net_models.dart`
- `lib/network/benchmark/benchmark_report.dart`

### 5. Product capability gaps remain obvious versus mature networking stacks

The repository overview still documents several capability gaps that matter if
the package is intended to compete with mature Flutter network stacks:

- Web is not currently supported
- no built-in business interceptor chain
- no declarative API client generation layer
- advanced network policy surfaces are still incomplete
  - proxy
  - certificate pinning / mTLS
  - DNS overrides
  - broader protocol/policy controls

These are not regressions, but they remain real product gaps.

Evidence:

- `FLUTTER_RUST_NET_OVERVIEW_ZH.md`

## Practical Assessment

The most accurate concise summary is:

- implementation maturity: medium-to-high
- local test health: good
- architecture transition status: largely landed
- admission readiness for real business integration: not yet fully closed
- remaining work type: mostly verification closure, terminology cleanup, and
  strategy alignment rather than basic capability coding

## Suggested Priority Order

1. Finish Android / iOS real-device and weak-network admission evidence, then
   write the formal business integration conclusion.
2. Turn real-`rhttp` / real-bridge verification into an easier repeatable lane
   instead of leaving it as mostly opt-in local setup.
3. Decide whether the project’s future main value line is the current
   thin-gateway `rhttp` path or the retained Rust-engine cache path, and reduce
   the current split narrative.
4. Gradually clean up legacy naming debt once the admission boundary is stable.
