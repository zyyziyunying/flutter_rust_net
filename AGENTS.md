# Repository Guidelines

## Scope
- This file covers `flutter_rust_net/` only.
- Read this file first when working in this package subtree.
- Workspace-level coordination rules live in `../AGENTS.md`.
- Read `../AGENTS.md` as needed when workspace-level coordination, ownership, or validation policy matters.
- This package is a member of the repo-root Dart workspace; keep `resolution: workspace` aligned with the root `pubspec.yaml`.

## Reverse Discovery
- If you start in `example/`, read `example/AGENTS.md` first, then come back here.
- Use this file for package-local rules.
- Use `../AGENTS.md` for workspace-wide coordination, ownership, and validation policy when relevant to the task.

## Project Structure & Module Organization
- `lib/network/` holds request models, gateway/policy, adapters, and clients.
- `tool/network_bench.dart` is the benchmark CLI entry.
- `tool/p1_non_loopback_bench.dart` is the fixed public-remote benchmark runner.
- `tool/p1_aggregate.dart` aggregates benchmark JSON outputs.
- `example/` is the standalone demo app for local/manual validation.
- `test/network/` contains core network behavior tests.
- `docs/` stores flutter_rust_net-specific docs (`progress/`, `dio_rust_test/`, design notes).

## Build, Test, and Development Commands
- `flutter pub get` - install or update package dependencies.
- Do not run `flutter analyze` by default; if static analysis is relevant, provide the exact command for the user to run.
- `flutter test` - run package tests.
- `dart run tool/network_bench.dart --help` - inspect benchmark options.
- `dart run tool/p1_non_loopback_bench.dart --help` - inspect the fixed public-remote benchmark runner.
- `cd example && flutter pub get && flutter run` - run example app for manual checks.

## Coding Style & Naming Conventions
- Follow `analysis_options.yaml` (`flutter_lints`) with 2-space indentation.
- Naming: `snake_case.dart` files, `PascalCase` types, `lowerCamelCase` members.
- Keep fallback/routing behavior explicit and deterministic in gateway logic.

## Testing Guidelines
- Keep tests behavior-focused and close to affected modules (`test/network/`).
- Add coverage for routing, fallback, and primary-channel compatibility-alias edge cases when logic changes.

## Documentation Update Policy
- Update progress/benchmark docs when they materially help the current work.
- Avoid repetitive doc noise when rerun results add no new insight.

## Commit & Pull Request Guidelines
- Use Conventional Commit prefixes (`feat:`, `fix:`, `docs:`, `test:`, `chore:`).
- Keep commits scoped; separate Dart API changes, generated bridge updates, and Rust engine updates when possible.
- PRs should include purpose, API/bridge impact, and exact validation commands run.
