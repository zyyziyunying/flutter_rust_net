# flutter_rust_net example

This app is a lightweight local benchmark launcher for `flutter_rust_net`.

It runs a built-in benchmark harness that automatically starts a local loopback
HTTP server, then compares Dio and Rust channels under preset scenarios.

## Run locally

```bash
cd flutter_rust_net/example
flutter pub get
flutter run
```

## Android Rust notes

`example/android/app/build.gradle.kts` now owns the Rust Android build wiring:
- builds `net_engine` via `cargo ndk` during `preBuild`
- packs generated `.so` into app `jniLibs`

Prerequisites:
- `cargo install cargo-ndk`
- Android NDK available in your Flutter/Android toolchain

## Presets

- `Dio smoke (small_json)`: verify baseline channel works.
- `Dio vs Rust (small_json)`: quick end-to-end compare.
- `Dio vs Rust (jitter c16 mif32)`: quick jitter sanity check for `mif=32`.

If Rust init fails on your device, keep `Require Rust init` off first.  
The app will still run Dio-only checks and print skip reasons in the log view.

## Real-device report upload

After a benchmark run, tap **Upload last report** to push the JSON report as a
multipart file to your server endpoint.

Default values in app:
- Upload URL: `http://47.110.52.208:7777/upload`
- Form field: `file`
- Login API: `POST /user/login`
- Built-in test account: `ziyunying / 123456` (used before upload)
- Upload headers: `token: <actual-token>` (+ `Authorization` 兼容保留)

You can edit these two fields in UI before uploading.
