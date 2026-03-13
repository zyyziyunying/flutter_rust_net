# net_engine cache module split

This document explains how `engine::cache` was split and what each file owns.

## Why split

The previous `cache.rs` mixed:

- public API (`lookup`, `store`, `revalidate`, `clear`)
- key building and normalization
- header and cache policy parsing
- metadata/body disk IO
- namespace prune/eviction
- all cache tests

That made the file hard to navigate and review.

## Split result

- `mod.rs`
  - Owns public surface and orchestration.
  - Keeps exported types and methods:
    - `DiskCache`
    - `CacheBodySource`
    - `CacheLookup`
    - `RESPONSE_CACHE_NAMESPACE`
- `headers.rs`
  - Header-level helpers only:
    - parse cache-control directives
    - query specific header values
    - normalize headers for persistence
    - merge headers during revalidation
- `key.rs`
  - Cache key logic only:
    - normalize URL
    - normalize request headers for key derivation
    - sanitize key for filesystem paths
    - deterministic hash function
- `policy.rs`
  - Cache policy logic only:
    - request-side cache disable checks
    - response-side `no-store` checks
    - TTL resolution from headers with fallback default TTL
- `storage.rs`
  - All file persistence helpers:
    - write/copy body files
    - atomic-like replacement
    - save/load metadata JSON
    - remove entry files
    - clear directory contents
- `prune.rs`
  - Namespace maintenance:
    - scan namespace entries
    - remove invalid/expired entries
    - enforce namespace byte budget with LRU-like eviction
- `tests.rs`
  - Behavior tests moved from old single file to keep implementation files focused.

## Invariants kept during split

- Public API and signatures are unchanged.
- Cache on-disk format is unchanged (`*.meta.json`, `*.body.bin`).
- Existing cache behavior and tests remain the same.
- `engine::client` call sites do not need changes.

## Validation run after split

From `native/rust/net_engine`:

```bash
cargo fmt --check
cargo test -q
```
