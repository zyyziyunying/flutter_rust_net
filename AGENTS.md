# Repository Guidelines

## Scope
- This file covers `flutter_rust_net/` only.
- Workspace-level coordination rules live in `../AGENTS.md`.

## Project Structure & Module Organization
- `lib/network/` holds request models, gateway/policy, adapters, and clients.
- `lib/rust_bridge/` contains generated flutter_rust_bridge Dart bindings.
- `tool/network_bench.dart` is the benchmark CLI entry.
- `example/` is the standalone demo app for local/manual validation.
- `test/network/` contains core network behavior tests.
- `docs/` stores flutter_rust_net-specific docs (`progress/`, `dio_rust_test/`, design notes).

## Build, Test, and Development Commands
- `flutter pub get` - install or update package dependencies.
- `flutter analyze` - run static analysis.
- `flutter test` - run package tests.
- `dart run tool/network_bench.dart --help` - inspect benchmark options.
- `cd example && flutter pub get && flutter run` - run example app for manual checks.
- `cd native/rust/net_engine && cargo test -q` - run Rust tests when bridge contracts or Rust logic change.

## Coding Style & Naming Conventions
- Follow `analysis_options.yaml` (`flutter_lints`) with 2-space indentation.
- Naming: `snake_case.dart` files, `PascalCase` types, `lowerCamelCase` members.
- Do not hand-edit generated files in `lib/rust_bridge/frb_generated*.dart` unless intentionally regenerating.
- Keep fallback/routing behavior explicit and deterministic in gateway logic.

## Testing Guidelines
- Keep tests behavior-focused and close to affected modules (`test/network/`).
- Add coverage for routing, fallback, and Rust-channel edge cases when logic changes.
- When Rust bridge contracts change, validate both `flutter test` and `cargo test -q` in `native/rust/net_engine`.

## Documentation Update Policy
- Update progress/benchmark docs when they materially help the current work.
- Avoid repetitive doc noise when rerun results add no new insight.

## Commit & Pull Request Guidelines
- Use Conventional Commit prefixes (`feat:`, `fix:`, `docs:`, `test:`, `chore:`).
- Keep commits scoped; separate Dart API changes, generated bridge updates, and Rust engine updates when possible.
- PRs should include purpose, API/bridge impact, and exact validation commands run.
