# flutter_rust_net example

This app is a lightweight local request lab and benchmark launcher for
`flutter_rust_net`.

It runs a built-in benchmark harness that automatically starts a local loopback
HTTP server, then compares Dio and the primary request channel (`rust`
compatibility alias, backed by `rhttp`) under preset scenarios.

It also owns the network-backed auth integration demos that exercise `common`
auth flows through `BytesFirstNetworkClient`, keeping `packages/common/example`
free from a direct `flutter_rust_net` dependency.

## Run locally

```bash
cd flutter_rust_net/example
flutter pub get
flutter run
```

## Presets

- `Dio smoke (small_json)`: verify baseline channel works.
- `Dio vs Primary (rust alias, small_json)`: quick end-to-end compare.
- `Dio vs Primary (rust alias, jitter c16)`: quick jitter sanity check.

If the primary request channel is unavailable on your device, keep
`Require primary request channel` off first. The app will still run Dio-only
checks and print skip reasons in the log view.

## Auth integration tabs

- `Auth App`: calls the HTTPS demo login endpoint, stores the session through
  `CommonAuth.secureStorage`, forces refresh, and recreates auth to verify
  storage bootstrap. Override `FRN_EXAMPLE_AUTH_LOGIN_URL`,
  `FRN_EXAMPLE_AUTH_LOGIN_USERNAME`, and `FRN_EXAMPLE_AUTH_LOGIN_PASSWORD` when
  pointing it at a real service. Prefer HTTPS; HTTP endpoints need matching
  Android cleartext or iOS ATS exceptions in the example app.
- `Auth Refresh`: uses an external `AuthTokenRefresher` backed by
  `BytesFirstNetworkClient` and calls `https://httpbin.org/uuid` to mint a demo
  access token.

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
