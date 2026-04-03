# Rhttp Dio Hard-Cut Review Findings

> Date: 2026-04-02
> Scope:
> - `docs/design/2026-04-02-rhttp-dio-hard-cut-design.md`
> - `docs/plan/2026-04-02-remove-frb-and-legacy-rust-surface-implementation-plan.md`
> Basis:
> - current worktree static review only
> - no code changes
> - no fresh test execution in this review note

## Verdict

This document is the static review snapshot captured on 2026-04-02.

Update on 2026-04-03:

- design and plan docs were revised to absorb these findings
- this file remains as review history and resolution traceability
- findings below are historical (pre-revision) severity ordering

Current status for document consistency:

- no known blocking contradiction remains between the revised staged
  design/plan docs and this review record
- this status is document-consistency only; implementation execution/validation
  is tracked by the plan tasks themselves

## Resolution Status (2026-04-03)

- Finding 1 absorbed by explicit `rust*` contract decisions in the design doc.
- Finding 2 absorbed by expanded benchmark/example/tooling scope in plan Task 3,
  including explicit benchmark API-signature verification for
  `runNetworkBenchmark(..., rustAdapter)`-related surfaces.
- Finding 3 absorbed by expanded active-doc cleanup scope in plan Task 5,
  including `docs/README.md`, `docs/progress/README.md`,
  `docs/progress/p2_status_2026-03-02.md`, and
  `docs/plan/cache_namespace_budget_governance_plan_2026-03-14.md`.
- Finding 4 absorbed by explicit Task 2/3 test-scope updates.
- Finding 5 absorbed by deterministic baseline/verification wording updates,
  including API-signature grep coverage in Task 3 and example build-path
  verification in Task 4 (not grep-only).
- Findings 6 and 7 remain mitigated by removing commit instructions from the
  plan.

## Historical Findings (Pre-Revision Snapshot)

### 1. The hard-cut docs undercount the surviving public `rust*` API surface

Evidence:

- `docs/design/2026-04-02-rhttp-dio-hard-cut-design.md:52-68`
- `docs/design/2026-04-02-rhttp-dio-hard-cut-design.md:146-155`
- `docs/plan/2026-04-02-remove-frb-and-legacy-rust-surface-implementation-plan.md:46-52`
- `lib/network/bytes_first_network_client.dart:127-197`
- `lib/network/network_gateway.dart:35-47`
- `lib/network/benchmark/benchmark_enums.dart:55-73`
- `lib/network/benchmark/benchmark_runner.dart:18-23`

Problem:

- The design says the intentional naming debt kept after hard cut is limited to
  `NetChannel.rust` and `enableRustChannel`.
- Current public / quasi-public API still exposes more `rust*` surface than
  that:
  - `BytesFirstNetworkClient.standard({ rustAdapter })`
  - `NetworkGateway.rustAdapter`
  - `runNetworkBenchmark(... rustAdapter: ...)`
  - `BenchmarkChannel.rust`
- These surfaces are neither listed in "APIs to keep" nor fully listed in
  "APIs to remove".

Impact:

- The repository can land in a state where implementation still exports
  unsupported compatibility names not covered by the hard-cut contract.
- Or the implementation removes them later without the current design/plan
  explicitly acknowledging the source break.

Recommended fix:

- Add an explicit post-cut compatibility matrix for every remaining `rust*`
  symbol, not only `NetChannel.rust` / `enableRustChannel`.
- Decide per symbol: keep, rename later, deprecate now, or remove in this cut.

### 2. Benchmark / example / tooling cleanup scope is materially underestimated

Evidence:

- `docs/plan/2026-04-02-remove-frb-and-legacy-rust-surface-implementation-plan.md:134-185`
- `docs/plan/2026-04-02-remove-frb-and-legacy-rust-surface-implementation-plan.md:187-248`
- `tool/network_bench.dart:54-92`
- `tool/network_bench.dart:162-204`
- `tool/p1_non_loopback_bench.dart:438-474`
- `tool/p1_aggregate/p1_aggregate_io.dart:96-149`
- `tool/p1_aggregate/p1_aggregate_models.dart:3-45`
- `tool/p1_aggregate/p1_aggregate_render.dart:19-80`
- `example/lib/apis/example_app_config.dart:78-117`
- `example/lib/pages/benchmark_page.dart:31-97`
- `test/network/network_realistic_flow_test.dart:13-260`
- `tool/_rust_tool_utils.dart:1-52`

Problem:

- Task 3 only lists benchmark core files, but current repo also has:
  - CLI flags for `initializeRust`, `requireRust`, `rustMaxInFlightTasks`,
    `rustCache*`
  - non-loopback benchmark orchestration
  - P1 aggregation tooling keyed on `rust` channels and `rustMaxInFlightTasks`
  - example benchmark presets and UI copy
  - realistic-flow tests asserting current benchmark semantics
  - `_rust_tool_utils.dart`, which becomes dead after Rust tool removal
- Task 4 only lists Gradle wiring and example README, which is not enough to
  close the current benchmark/tooling surface.

Impact:

- Following the current plan as written will leave either:
  - compile errors after benchmark model cleanup, or
  - stale tooling that still documents / emits removed legacy Rust semantics.

Recommended fix:

- Expand Task 3/4 scope to include all benchmark callers, aggregators, CLI
  wrappers, example presets, and helper tooling that reference removed fields.
- Define whether benchmark after hard cut remains:
  - `dio` vs primary-channel compare only, or
  - a smaller request-path smoke tool with all Rust-engine/cache config removed.

## Medium Severity Findings

### 3. Active docs cleanup scope is incomplete and would leave conflicting current-state docs

Evidence:

- `docs/plan/2026-04-02-remove-frb-and-legacy-rust-surface-implementation-plan.md:250-309`
- `docs/README.md:5-29`
- `docs/dio_rust_test/network_route_strategy_2026-02-24.md:3-15`
- `docs/dio_rust_test/network_realistic_benchmark_runbook_2026-02-24.md:7-21`
- `docs/flutter_rust_network_layer_design.md:12-15`
- `docs/flutter_rust_network_layer_design.md:71-83`
- `docs/problems/2026-04-02-rhttp-thin-gateway-design-review-status-check.md:13-22`
- `docs/progress/p1_status_2026-02-25.md:30-38`
- `docs/progress/rust_lifecycle_scope_status_2026-03-12.md:9-15`
- `docs/progress/real_device_test_commands_2026-03-02.md:10-16`

Problem:

- Task 5 covers README, overview, AGENTS, one problems doc, and plan README.
- It does not cover current active entry-point docs that still describe retained
  FRB / `RustAdapter` / `net_engine` as present current state.
- The gap is not limited to `docs/flutter_rust_network_layer_design.md` and a
  few `docs/progress/*` records.
- `docs/README.md` and active progress docs still direct readers to
  `docs/dio_rust_test/*`, where several documents remain written as current
  routing/runbook guidance for the retained Rust path.
- `docs/README.md` still points readers to
  `docs/flutter_rust_network_layer_design.md` as the current effective design
  document, but that file still describes Rust main-channel / FRB architecture.
- `docs/README.md` also still links to
  `docs/problems/rust_net_engine_blockers_2026-03-13.md`, while the current
  file only exists under `docs/problems/archive/`.

Impact:

- After hard cut, repo entry-point docs can still contradict the new README and
  AGENTS guidance.
- Users entering through `docs/README.md` will get a stale architecture story.
- Some historical benchmark/sample docs may still be worth keeping, but they
  cannot stay linked from active entry points as current guidance.

Recommended fix:

- Add explicit handling for active-doc entry points:
  - update or archive `docs/flutter_rust_network_layer_design.md`
  - update `docs/README.md`
  - update active `docs/progress/*` docs that still describe current retained
    Rust ownership
  - update active `docs/problems/*` docs that currently treat retained Rust
    surface as current-state fact
  - decide whether `docs/dio_rust_test/*` should be archived, relabeled as
    pre-hard-cut history, or removed from active entry-point navigation

### 4. The test cleanup list is incomplete

Evidence:

- `docs/plan/2026-04-02-remove-frb-and-legacy-rust-surface-implementation-plan.md:71-132`
- `docs/plan/2026-04-02-remove-frb-and-legacy-rust-surface-implementation-plan.md:134-185`
- `test/network/network_smoke_flow_test.dart:11-103`
- `test/network/network_realistic_flow_test.dart:13-260`

Problem:

- Task 2 lists Rust/FRB tests to delete, but misses
  `test/network/network_smoke_flow_test.dart`, which still directly imports
  `network/rust_adapter.dart`.
- Task 3 updates benchmark semantics but does not include
  `test/network/network_realistic_flow_test.dart`, which asserts current
  benchmark `rust` channel behavior.

Impact:

- The plan is not executable as a complete cleanup script.
- A developer following it can remove runtime surface and still be left with
  failing or misleading tests outside the listed scope.

Recommended fix:

- Add the missing tests to the removal / rewrite list.
- Reframe test tasks around affected surface areas instead of a narrower
  file shortlist.

### 5. Several TDD / verification steps are not reliably executable as written

Evidence:

- `docs/plan/2026-04-02-remove-frb-and-legacy-rust-surface-implementation-plan.md:23-42`
- `docs/plan/2026-04-02-remove-frb-and-legacy-rust-surface-implementation-plan.md:84-109`
- `docs/plan/2026-04-02-remove-frb-and-legacy-rust-surface-implementation-plan.md:205-240`
- `docs/plan/2026-04-02-remove-frb-and-legacy-rust-surface-implementation-plan.md:266-292`
- `lib/network/network_gateway.dart:103-124`

Problem:

- Several steps say "Expected: FAIL" for reasons that are not deterministic in
  the current repo state.
- Example:
  - Task 1 removes tests that depend on legacy API, but that alone may not make
    the suite fail before implementation.
  - Task 2 expects surviving-contract tests to fail if they were only covered by
    Rust tests, but that is not guaranteed.
- The `rg` verification patterns in Task 4/5 are also too narrow; they do not
  detect remaining legacy terms such as:
  - `initializeRust`
  - `requireRust`
  - `BenchmarkChannel.rust`
  - `rustMaxInFlightTasks`
  - `rustCache*`

Impact:

- The plan can produce false confidence:
  - red step may not actually go red
  - cleanup verification may pass while large legacy surface still remains

Recommended fix:

- Use deterministic red-green targets:
  - first add explicit tests for the exact removed surface
  - then remove the surface
  - then rerun the narrowed suite
- Expand grep-based cleanup verification to cover all remaining legacy Rust
  benchmark/tooling vocabulary, not only FRB filenames and `RustAdapter`.

### 6. Task 1-4 commit command risk is mitigated by removing commit steps

Evidence:

- `docs/plan/2026-04-02-remove-frb-and-legacy-rust-surface-implementation-plan.md`
- the plan now states that commit strategy is intentionally omitted and managed
  by the executor
- package repo root verified in the current worktree as
  `/Users/zyyziyunying/harrypet_flutter/flutter_rust_net`

Original problem:

- Task 1-4 previously ran from the package repository root, but their commit
  commands used `git add flutter_rust_net/...`.
- From the package root, those pathspecs would not match the edited files,
  because `flutter_rust_net/` is not a child path inside that repository.

Current status:

- Mitigated by plan revision.
- The implementation plan no longer prescribes Task 1-4 commit commands, so the
  incorrect package-root pathspec risk is no longer part of the executable
  plan.

Follow-up guidance:

- If commit instructions are ever reintroduced, they should use
  package-root-relative paths such as `lib/...`, `test/...`, `tool/...`,
  `example/...`, and `docs/...`.

### 7. Task 5 nested-repo commit risk is mitigated by removing commit steps

Evidence:

- `docs/plan/2026-04-02-remove-frb-and-legacy-rust-surface-implementation-plan.md`
- the plan now states that commit strategy is intentionally omitted and managed
  by the executor
- package repo root verified in the current worktree as
  `/Users/zyyziyunying/harrypet_flutter/flutter_rust_net`
- superproject working tree verified in the current worktree as
  `/Users/zyyziyunying/harrypet_flutter`

Original problem:

- Task 5 previously switched to `/Users/zyyziyunying/harrypet_flutter` and
  attempted to stage both workspace `AGENTS.md` and package-local doc changes
  in one `git add` / `git commit` step.
- But `flutter_rust_net/` is a nested git repository under that superproject,
  so the outer repository cannot stage the package repository's internal file
  changes as normal tracked file content.

Current status:

- Mitigated by plan revision.
- The implementation plan no longer prescribes a combined Task 5 commit step,
  so it no longer encodes an invalid cross-repository staging workflow.

Follow-up guidance:

- If commit instructions are ever reintroduced, they should either:
  - stay fully scoped to the package repository, or
  - explicitly separate package-repo commits from outer-workspace submodule
    pointer updates.

## Notes

- This review did not find a direct implementation conflict in keeping
  `NetChannel.rust` / `enableRustChannel` as compatibility names after the hard
  cut.
- The main problem is not those two names themselves; it is that the current
  design and implementation plan do not yet account for the broader surviving
  `rust*` surface that still exists in the repository today.
