# Rhttp Download Bench Design

**Date:** 2026-04-07

## Goal

Add a repository-local benchmark that compares `dio` and `rhttp` for
download-to-file workloads without routing through the current
`NetworkGateway.startTransferTask()` abstraction.

## Context

- The current Rust-backed channel in this repository is request-only.
- `NetworkGateway.startTransferTask()` is intentionally `dio`-only in V1 and
  rejects forced Rust transfer routing.
- Fresh public-remote request benchmarks on this Mac show `dio` and `rust`
  staying close for `small_json` and `jitter_latency`, so request-path results
  are not enough to evaluate `rhttp`'s claimed large-download advantage.

## Accepted Constraints

- Do not modify the existing gateway transfer abstraction.
- Do not bind the benchmark to `NetworkGateway.startTransferTask()`.
- Do not add UI.
- Do not make resume / cancel / progress comparison part of V1.
- Default to local loopback as the primary benchmark baseline.
- Allow optional `--base-url` for compatible remote verification.

## Proposed Tool

Create a standalone CLI benchmark:

- `tool/rhttp_download_bench.dart`

The tool should compare two explicit paths:

- `dio`: download response bytes directly to a temporary file.
- `rhttp`: use `rhttp` stream response APIs and write the stream to a temporary
  file.

The benchmark is intentionally a client-capability benchmark, not a product
gateway benchmark.

## Server Strategy

Reuse the repository's benchmark scenario server and add a dedicated download
endpoint, for example:

- `/bench/download-file`

The endpoint should:

- Return binary content of a configurable size.
- Support configurable chunk size.
- Support optional per-chunk delay.
- Emit a deterministic payload so size and checksum verification are stable.

This keeps the local baseline reproducible and avoids conflating client-side
download behavior with public-network noise.

## CLI Shape

Recommended arguments:

- `--base-url=...`
- `--channels=dio,rhttp`
- `--file-bytes=16777216`
- `--requests=3`
- `--warmup=1`
- `--concurrency=1`
- `--chunk-bytes=65536`
- `--chunk-delay-ms=0`
- `--output=build/rhttp_download_bench.json`

Default behavior:

- No `--base-url`: start local loopback download server.
- With `--base-url`: run against the provided compatible remote endpoint.

## Output Contract

The benchmark should emit a JSON report with:

- Run metadata:
  - `baseUrl`
  - `serverMode`
  - `fileBytes`
  - `requests`
  - `warmup`
  - `concurrency`
  - `chunkBytes`
  - `chunkDelayMs`
  - `startedAt`
  - `finishedAt`
- Per-channel results:
  - `successCount`
  - `failureCount`
  - `downloadP50Ms`
  - `downloadP95Ms`
  - `avgMs`
  - `bytesPerSecond`
  - `throughputMbps`
  - `fileSizeVerifiedCount`
  - `checksumVerifiedCount`
  - `outputFileMode`

V1 should only count successful download-to-file completions.

## Validation Rules

Each measured download must:

- Write into a temporary file.
- Verify final file size.
- Verify deterministic checksum.
- Clean up benchmark temp files after verification.

This ensures the benchmark measures real file download completion instead of
in-memory response handling.

## Test Scope

Required automated coverage:

- Local download endpoint returns the configured byte count.
- `dio` benchmark path produces files with the expected size and checksum.
- `rhttp` benchmark path produces files with the expected size and checksum.
- Channel failures are recorded as failures in the report.

Required manual verification:

- One local loopback benchmark run with `dio,rhttp`.
- One optional remote run only when a compatible remote download endpoint exists.

## Non-Goals

- No integration with current gateway transfer routing.
- No resume support benchmarking.
- No cancel / progress parity study in V1.
- No attempt to prove end-user production gains from one run alone.

## Success Criteria

V1 is complete when the repository contains a repeatable standalone download
benchmark that:

- runs locally without modifying the gateway transfer abstraction,
- produces a JSON report,
- and compares `dio` and `rhttp` on verified download-to-file workloads.
