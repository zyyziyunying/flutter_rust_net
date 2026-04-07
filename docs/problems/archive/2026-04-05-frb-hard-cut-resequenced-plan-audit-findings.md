# FRB Hard-Cut Resequenced Plan Audit Findings

> Date: 2026-04-05
> Scope:
> - `docs/plan/archive/2026-04-04-remove-frb-hard-cut-resequenced-plan.md`
> - current `flutter_rust_net` worktree
> Basis:
> - static repository audit
> - targeted file-by-file review across runtime/API, benchmark/tooling, example,
>   dependencies, and docs
> - fresh baseline command execution during this audit
> - no code changes in this review note
>
> 2026-04-07 update:
> - docs taxonomy was tightened after this audit
> - historical status/runbook docs were reframed as historical snapshots
> - the package/API `rustAdapter` seam noted in Finding 1 no longer reproduces in the current worktree
> - this file is retained as a historical audit record, not an active problem doc

## Verdict

The FRB hard cut is largely complete at the dependency/runtime/tree level:

- package-local FRB/runtime/native-engine code is no longer present
- `flutter pub get`, package `flutter test`, example `flutter pub get`, example
  widget test, and benchmark/tool help entrypoints all pass

However, the repository does not fully satisfy the resequenced plan's stated
end state yet.

The main remaining gap is:

1. active public API still preserves `rustAdapter`-named seams

Additional cleanup remains, but the original concern needs narrower wording:

2. some historical docs still read with current-tone internal sections even
   though repository entrypoints already classify them as legacy/pre-hard-cut
   material
3. optional real-`rhttp` test guidance still leaks FRB-branded operational
   naming into test skip/help text, although active docs already mark that lane
   as opt-in

## Findings

### 1. High: public hard-cut seam is still not clean

Plan conflict:

- Binding Decision 2
- Phase 1 acceptance
- benchmark-facing seam cleanup intent in Phase 2

Evidence:

- `lib/network/bytes_first_network_client.dart:126`
- `lib/network/bytes_first_network_client.dart:135`
- `lib/network/network_gateway.dart:42`
- `lib/network/network_gateway.dart:58`
- `lib/network/benchmark/benchmark_runner.dart:17`
- `test/network/benchmark_runner_test.dart:87`
- `test/network/network_gateway_transfer_state_test.dart:31`

Problem:

- The active package still accepts `rustAdapter` in public or quasi-public API:
  - `BytesFirstNetworkClient.standard({ rustAdapter })`
  - `NetworkGateway({ rustAdapter })`
  - `NetworkGateway.rustAdapter`
  - `runNetworkBenchmark(..., rustAdapter: ...)`
- These are not just historical names in docs; they remain supported behavior in
  live code and tests.

Impact:

- The repository still exposes a business-facing legacy seam that implies old
  Rust/FRB ownership, which is exactly the seam the plan says should be removed.
- Current status claims that the surviving public seam cleanup is complete are
  therefore too strong.

Recommended fix:

- Remove active `rustAdapter` API entrypoints/getters from package code.
- Rewrite the remaining tests to use only neutral primary-adapter seams.
- If a temporary compatibility shim is intentionally retained, document it as an
  explicit deferral instead of claiming the phase is complete.

### 2. Medium: historical docs still need cleaner legacy framing internally

Plan conflict:

- Phase 6 cleanup intent

Evidence:

- `docs/progress/archive/frb_hard_cut_status_2026-04-04.md:9`
- `docs/progress/archive/frb_hard_cut_status_2026-04-04.md:42`
- `docs/progress/archive/rust_lifecycle_scope_status_2026-03-12.md:7`
- `docs/progress/archive/rust_lifecycle_scope_status_2026-03-12.md:38`
- `docs/progress/archive/rust_lifecycle_scope_status_2026-03-12.md:53`
- `docs/progress/archive/real_device_test_commands_2026-03-02.md:10`
- `docs/progress/archive/real_device_test_commands_2026-03-02.md:34`
- `docs/progress/archive/real_device_test_commands_2026-03-02.md:115`

Problem:

- The repo's active entrypoints already classify these documents as
  legacy/pre-hard-cut history:
  - `docs/README.md`
  - `docs/progress/README.md`
  - `FLUTTER_RUST_NET_OVERVIEW_ZH.md`
- But some historical docs still read internally like active/current guidance
  even after the added historical disclaimer:
  - `rust_lifecycle_scope_status_2026-03-12.md` still has active "current
    status", "In Progress", and "Next" sections for `RustAdapter` /
    `RustBridgeApi`
  - `real_device_test_commands_2026-03-02.md` still contains deleted commands,
    removed CLI flags, and current-tone runbook wording

Impact:

- This is documentation hygiene debt, not strong evidence that the repository's
  main active fact sources are still routing readers to FRB/runtime as current
  package contract.
- The risk is mainly that a reader who opens the historical files directly can
  still encounter current-tone legacy guidance.

Recommended fix:

- Either archive these docs, or rewrite them so they read unambiguously as
  historical records instead of current guidance.
- This concern should be framed as legacy-doc cleanup, not by itself as proof
  that all active status entrypoints are inaccurate.

### 3. Low: optional real-rhttp validation lane still uses FRB-branded env guidance in test skip/help text

Plan conflict:

- Validation claim after hard cut
- Phase 6 current-contract wording

Evidence:

- `test/network/rhttp_adapter_test.dart:290`
- `test/network/request_body_channel_consistency_test.dart:269`

Problem:

- The opt-in real-`rhttp` tests still tell contributors to set
  `FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR`.
- During this audit's fresh `flutter test` run, those tests skipped with that
  exact message.
- Active docs already make the validation boundary explicit and describe the
  real-`rhttp` lane as opt-in rather than default-covered.

Impact:

- Even though package-local FRB code is gone, the current validation surface
  still presents FRB-branded setup in repo-authored test messages.
- This is a wording cleanup issue in the optional lane, not strong evidence
  that active docs are claiming the lane is covered by default.

Recommended fix:

- Replace repo-authored skip/help text with neutral real-`rhttp` wording if the
  upstream dependency still needs the same env var.
- In active docs, describe that lane as opt-in and avoid presenting FRB naming
  as part of the package contract.

### 4. Low: plan lifecycle concern depends on the status overclaim, not as a standalone defect

Plan conflict:

- `docs/plan/README.md` maintenance rule

Evidence:

- `docs/progress/archive/frb_hard_cut_status_2026-04-04.md:61`
- `docs/progress/archive/frb_hard_cut_status_2026-04-04.md:65`
- `docs/plan/README.md:14`
- `docs/plan/README.md:25`

Problem:

- `docs/plan/README.md` says completed plans should be moved out of active plan
  space.
- But the stronger repository evidence is that the hard cut still has at least
  one real remaining cleanup item: the active `rustAdapter` seam.
- Once that seam is acknowledged as still open, keeping the resequenced plan in
  active plan space is not by itself inconsistent.

Impact:

- The real issue is the status wording in
  `docs/progress/archive/frb_hard_cut_status_2026-04-04.md`, not the mere existence of
  the plan in active plan space.

Recommended fix:

- First correct the hard-cut status wording to reflect the remaining seam
  cleanup.
- Archive or relabel the plan only after the remaining seam cleanup actually
  lands.

## Validation Run In This Audit

Executed and passed:

- `flutter pub get`
- `flutter test`
- `cd example && flutter pub get`
- `cd example && flutter test test/widget_test.dart`
- `dart run tool/network_bench.dart --help`
- `dart run tool/p1_non_loopback_bench.dart --help`
- `dart run tool/p1_aggregate.dart --help`

Observed during validation:

- optional real-`rhttp` tests were skipped because
  `FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR` was not set

Not executed:

- `flutter analyze`

## Audit Summary

This repository is close to the intended post-hard-cut state, but not yet in a
strictly "all phases complete" state under the 2026-04-04 resequenced plan.

The dependency/runtime removal work is effectively done. The remaining work is
primarily contract cleanup, plus some wording hygiene:

- remove active `rustAdapter`-named public seams
- tighten status wording so it does not overclaim closure while that seam
  remains
- continue neutralizing FRB-branded wording in the optional real-`rhttp`
  validation lane
