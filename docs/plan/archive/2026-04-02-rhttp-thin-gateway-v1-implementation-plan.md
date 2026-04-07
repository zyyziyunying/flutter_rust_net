# Rhttp Thin Gateway V1 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deliver the phase-1 `rhttp + Dio` thin-gateway migration without hidden API drift by locking the retained request contract first, then replacing the request transport, and only then cleaning up public/documented legacy surfaces.

**Architecture:** Phase 1 keeps the business-facing request contract (`NetRequest`, `NetResponse`, `NetworkGateway.request`, `BytesFirstNetworkClient.request*`) and intentionally narrows everything else. The migration should proceed seam-by-seam: first make transfer behavior explicitly Dio-only, then add `RhttpAdapter` behind the existing `NetChannel.rust` routing name, then reconcile `BytesFirstNetworkClient`, exports, example, benchmark, and docs with the new ownership model.

**Tech Stack:** Flutter/Dart, `dio`, `rhttp`, `flutter_test`

---

### Task 1: Make transfer behavior truly Dio-only in V1

**Files:**
- Modify: `flutter_rust_net/test/network/network_gateway/network_gateway_transfer_task_test.dart`
- Modify: `flutter_rust_net/test/network/network_gateway_transfer_state_test.dart`
- Modify: `flutter_rust_net/lib/network/network_gateway.dart`

**Step 1: Write the failing tests**

Add or update tests so that phase-1 transfer behavior is explicit:

- auto routing keeps transfer on Dio even when `enableRustChannel == true`
- `forceChannel: NetChannel.dio` still works
- `forceChannel: NetChannel.rust` fails deterministically with an explicit unsupported `NetException`
- `pollTransferEvents()` and `cancelTransferTask()` stop probing the primary request adapter

**Step 2: Run tests to verify they fail**

Run:

```bash
cd /Users/zyyziyunying/harrypet_flutter/flutter_rust_net && flutter test test/network/network_gateway/network_gateway_transfer_task_test.dart test/network/network_gateway_transfer_state_test.dart
```

Expected: FAIL because current `NetworkGateway` still routes transfer work through `rustAdapter`.

**Step 3: Write the minimal implementation**

Update `flutter_rust_net/lib/network/network_gateway.dart` so that:

- `startTransferTask()` never routes to the primary request adapter in V1
- `forceChannel: NetChannel.rust` throws a deterministic unsupported error instead of silently rerouting
- `pollTransferEvents()` only polls Dio-backed transfer state
- `cancelTransferTask()` only cancels Dio-backed transfer tasks

Keep request fallback logic untouched in this task.

**Step 4: Run tests to verify they pass**

Run:

```bash
cd /Users/zyyziyunying/harrypet_flutter/flutter_rust_net && flutter test test/network/network_gateway/network_gateway_transfer_task_test.dart test/network/network_gateway_transfer_state_test.dart
```

Expected: PASS.

**Step 5: Commit**

```bash
git add flutter_rust_net/lib/network/network_gateway.dart flutter_rust_net/test/network/network_gateway/network_gateway_transfer_task_test.dart flutter_rust_net/test/network/network_gateway_transfer_state_test.dart
git commit -m "fix: make transfer path dio only in thin gateway v1"
```

### Task 2: Introduce `RhttpAdapter` with the existing bytes-first contract

**Files:**
- Modify: `flutter_rust_net/pubspec.yaml`
- Create: `flutter_rust_net/lib/network/rhttp_adapter.dart`
- Modify: `flutter_rust_net/lib/network/request_body_codec.dart`
- Create: `flutter_rust_net/test/network/rhttp_adapter_test.dart`
- Modify: `flutter_rust_net/test/network/request_body_channel_consistency_test.dart`

**Step 1: Write the failing tests**

Add tests that prove `RhttpAdapter`:

- reuses `encodeRequestBody()` semantics for `body`, `bodyBytes`, and `String`
- does not auto-add or rewrite `content-type`
- maps success and failure into existing `NetResponse` / `NetException` shapes
- keeps V1 request metadata behavior aligned with the design:
  - `expectLargeResponse` is a no-op
  - `bodyFilePath == null`
  - `fromCache == false`

**Step 2: Run tests to verify they fail**

Run:

```bash
cd /Users/zyyziyunying/harrypet_flutter/flutter_rust_net && flutter pub get && flutter test test/network/rhttp_adapter_test.dart test/network/request_body_channel_consistency_test.dart
```

Expected: FAIL because `RhttpAdapter` does not exist yet and the new contract is not implemented.

**Step 3: Write the minimal implementation**

Implement `flutter_rust_net/lib/network/rhttp_adapter.dart` so that:

- it implements `NetAdapter`
- request bodies always go through `encodeRequestBody()`
- request execution uses `rhttp` without body/helper shortcuts that change payload semantics
- response mapping preserves existing `NetResponse` fields
- V1 request metadata stays conservative (`bodyFilePath: null`, `fromCache: false`)

Only add the package dependency and the adapter needed for the request path. Do not touch transfer behavior here.

**Step 4: Run tests to verify they pass**

Run:

```bash
cd /Users/zyyziyunying/harrypet_flutter/flutter_rust_net && flutter test test/network/rhttp_adapter_test.dart test/network/request_body_channel_consistency_test.dart
```

Expected: PASS.

**Step 5: Commit**

```bash
git add flutter_rust_net/pubspec.yaml flutter_rust_net/lib/network/rhttp_adapter.dart flutter_rust_net/test/network/rhttp_adapter_test.dart flutter_rust_net/test/network/request_body_channel_consistency_test.dart
git commit -m "feat: add rhttp request adapter for thin gateway"
```

### Task 3: Route request traffic through `RhttpAdapter` while preserving fallback rules

**Files:**
- Modify: `flutter_rust_net/lib/network/network_gateway.dart`
- Modify: `flutter_rust_net/lib/network/net_adapter.dart`
- Modify: `flutter_rust_net/test/network/network_gateway/network_gateway_request_test.dart`
- Modify: `flutter_rust_net/test/network/network_gateway/network_gateway_test_helpers.dart`

**Step 1: Write the failing tests**

Extend request-path tests so that:

- `enableRustChannel == true` routes regular requests to the new primary adapter
- eligible errors still fall back from the primary path to Dio
- non-eligible errors still fail directly
- route metadata still uses the compatibility name `NetChannel.rust`
- request fallback safety remains unchanged for non-idempotent requests

**Step 2: Run tests to verify they fail**

Run:

```bash
cd /Users/zyyziyunying/harrypet_flutter/flutter_rust_net && flutter test test/network/network_gateway/network_gateway_request_test.dart
```

Expected: FAIL because request-path wiring still assumes the old `RustAdapter` lifecycle and behavior.

**Step 3: Write the minimal implementation**

Update `NetworkGateway` so the request-primary adapter can be `RhttpAdapter` while retaining:

- `NetChannel.rust` as the compatibility route name
- current fallback eligibility rules
- current idempotency checks
- current request route metadata shape

If `NetAdapter.isReady` remains on the shared abstraction, keep its use scoped to request routing only.

**Step 4: Run tests to verify they pass**

Run:

```bash
cd /Users/zyyziyunying/harrypet_flutter/flutter_rust_net && flutter test test/network/network_gateway/network_gateway_request_test.dart
```

Expected: PASS.

**Step 5: Commit**

```bash
git add flutter_rust_net/lib/network/network_gateway.dart flutter_rust_net/lib/network/net_adapter.dart flutter_rust_net/test/network/network_gateway/network_gateway_request_test.dart flutter_rust_net/test/network/network_gateway/network_gateway_test_helpers.dart
git commit -m "refactor: route request traffic through primary rhttp adapter"
```

### Task 4: Reconcile `BytesFirstNetworkClient` and public exports with the new boundary

**Files:**
- Modify: `flutter_rust_net/lib/network/bytes_first_network_client.dart`
- Modify: `flutter_rust_net/lib/flutter_rust_net.dart`
- Modify: `flutter_rust_net/test/network/bytes_first_network_client_test.dart`

**Step 1: Write the failing tests**

Update client-facing tests to match the chosen V1 boundary:

- `standard()` remains the safe Dio default
- request helpers still preserve `baseUrl`, `forceChannel`, and bytes-first decoding behavior
- `standardWithRust()` and `rustAdapter` are either explicitly deprecated shim surfaces or intentionally removed from the compatibility promise
- no test should require request-path engine initialization as part of the new primary transport contract

**Step 2: Run tests to verify they fail**

Run:

```bash
cd /Users/zyyziyunying/harrypet_flutter/flutter_rust_net && flutter test test/network/bytes_first_network_client_test.dart
```

Expected: FAIL until the public surface is aligned with the phase-1 decision.

**Step 3: Write the minimal implementation**

Refactor `BytesFirstNetworkClient` and exports to match the design:

- keep `standard()` as Dio-safe default
- choose one explicit compatibility strategy for `standardWithRust()` / `rustAdapter`:
  - temporary deprecated shim with clearly limited semantics, or
  - removal from public promise with updated docs/tests
- stop requiring request-path Rust-engine initialization in the normal request happy path

This task must not silently preserve misleading `RustAdapter`-shaped semantics.

**Step 4: Run tests to verify they pass**

Run:

```bash
cd /Users/zyyziyunying/harrypet_flutter/flutter_rust_net && flutter test test/network/bytes_first_network_client_test.dart test/network/network_gateway/network_gateway_request_test.dart
```

Expected: PASS.

**Step 5: Commit**

```bash
git add flutter_rust_net/lib/network/bytes_first_network_client.dart flutter_rust_net/lib/flutter_rust_net.dart flutter_rust_net/test/network/bytes_first_network_client_test.dart
git commit -m "refactor: align bytes first client with thin gateway v1"
```

### Task 5: Clean up example, benchmark, and docs so they stop over-claiming Rust-engine ownership

**Files:**
- Modify: `flutter_rust_net/example/lib/pages/request_lab_page.dart`
- Modify: `flutter_rust_net/lib/network/benchmark/benchmark_runner.dart`
- Modify: `flutter_rust_net/README.md`
- Modify: `flutter_rust_net/FLUTTER_RUST_NET_OVERVIEW_ZH.md`
- Modify: `flutter_rust_net/docs/archived/2026-04-01-flutter-rust-net-rhttp-thin-gateway-design.md`

**Step 1: Write the failing tests or acceptance checks**

Add lightweight tests where practical, and define manual acceptance for the rest:

- example request lab no longer requires explicit request-path Rust init/shutdown for normal requests
- benchmark flow either stays on the legacy path intentionally or is explicitly marked deferred
- README and overview no longer describe the package as “our own Rust engine plus FRB” for the request path

**Step 2: Run the relevant checks to verify drift exists**

Run:

```bash
cd /Users/zyyziyunying/harrypet_flutter/flutter_rust_net && flutter test test/network/bytes_first_network_client_test.dart test/network/network_gateway/network_gateway_transfer_task_test.dart
```

Expected: PASS for code-level contract checks. Remaining failures are documentation/acceptance gaps to close in this task.

**Step 3: Write the minimal implementation**

Update example, benchmark, and docs so they match the actual V1 architecture:

- request path is `rhttp + Dio`
- transfer path is Dio-only in V1
- request-path native lifecycle is no longer a supported business-facing feature
- deferred legacy surfaces are called out explicitly instead of implied as still-first-class

**Step 4: Run the package validation**

Run:

```bash
cd /Users/zyyziyunying/harrypet_flutter/flutter_rust_net && flutter test
```

Expected: PASS.

**Step 5: Commit**

```bash
git add flutter_rust_net/example/lib/pages/request_lab_page.dart flutter_rust_net/lib/network/benchmark/benchmark_runner.dart flutter_rust_net/README.md flutter_rust_net/FLUTTER_RUST_NET_OVERVIEW_ZH.md flutter_rust_net/docs/archived/2026-04-01-flutter-rust-net-rhttp-thin-gateway-design.md
git commit -m "docs: align thin gateway examples and docs with v1 scope"
```

### Task 6: Final verification and progress write-back

**Files:**
- Modify: `flutter_rust_net/docs/progress/` entry if needed for execution status

**Step 1: Run full validation**

Run:

```bash
cd /Users/zyyziyunying/harrypet_flutter/flutter_rust_net && flutter test
```

Expected: PASS.

**Step 2: Record what was intentionally deferred**

Capture any remaining legacy items that are not part of V1, especially:

- package-local FRB/native-engine removal outside the request path
- benchmark legacy flows still using `RustAdapter`, if intentionally deferred
- any temporary shim kept only for transition

**Step 3: Commit**

```bash
git add flutter_rust_net/docs/progress
git commit -m "docs: record thin gateway v1 execution status"
```
