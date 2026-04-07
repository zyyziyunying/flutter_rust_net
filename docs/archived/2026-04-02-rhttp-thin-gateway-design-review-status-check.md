# Rhttp Thin Gateway Design Review Status Check

> Date: 2026-04-02
> Status: Historical pre-hard-cut status check
> Superseded by:
> - `docs/progress/archive/frb_hard_cut_status_2026-04-04.md`
> - `docs/flutter_rust_network_layer_design.md`

## Historical Boundary

This document checked the repository before the FRB hard cut finished.

Statements here about retained `RustAdapter`, root-barrel legacy exports,
package-local FRB ownership, or `native/rust/net_engine` are no longer current.

## What Changed After This Check

The repository has since advanced to:

- delete Dart-side FRB/runtime files
- remove root-level legacy runtime surface from the active package
- remove package-local FRB dependency, codegen/build scripts, and native-engine tree
- keep only the thin-gateway `rhttp + Dio` contract in active docs and entry points

## What Still Matters

The remaining durable point from this review is verification discipline:

- default `flutter test` coverage and opt-in real-`rhttp` coverage should remain clearly separated
- compatibility names such as `NetChannel.rust` should be described as aliases, not runtime ownership
