# Qingniao SMS

A local-first SMS and MMS client for Android. Flutter provides the Material 3 interface, Kotlin integrates platform messaging, and Rust handles text analysis, search and cryptographic modules.

[简体中文](README.md) · **English**

Package: `com.blue.qingniao`. Minimum: Android 12, API 31. Android is the only app target; desktop build scripts support cross-compilation rather than desktop clients.

## Features

| Area | Current implementation |
| --- | --- |
| SMS | Default messaging role, dual SIM, multipart messages, send/delivery states, drafts, search and paging |
| Conversations | Selection, copy, mark all read, pin, archive and block; configurable physical swipes, defaulting to trash on left and read on right |
| Codes | On-device extraction, one-tap copy, sensitive clipboard and optional recycling after reading |
| Trash | Restore, permanent deletion and retention; preserve local records when provider deletion cannot be confirmed |
| Scheduling | Persistent tasks, alarms and startup/reboot recovery; fallback without exact-alarm access |
| MMS | Mixed threads, group recipients, attachment previews and platform transport; carrier validation required |
| Notifications | Reply, read and copy actions; request promoted notifications where supported, with system-controlled presentation |
| Appearance | Material 3 components and Expressive shapes, Monet, six reference palettes, dark/AMOLED themes and three adaptive icons |
| Fonts | System, HarmonyOS Sans and Google Sans, with HarmonyOS Sans fallback for Chinese |
| Languages | Chinese, English, Hindi, Spanish, Arabic, French, Bengali, Portuguese, Russian and Urdu; RTL support |
| Optional networking | Self-hosted encrypted sync and FCM sync hints; disabled by default and require configuration |

Recycling applies to codes unread when loaded and fully visible in the foreground conversation for about two seconds. Scrolling, backgrounding and selection interrupt observation; marking all read does not trigger it. Notification expiry is separate from message recycling. Missed scheduled messages remain available for review instead of being sent in a burst after reboot.

## Aurora motion and rendering

Aurora is an application-level scheduler built on Flutter frame scheduling and GPU rendering. It does not modify Android's compositor or drivers.

The star background uses a bundled fragment shader with constant work per pixel and one draw call. Android enables Impeller; the engine selects the available GPU backend. A bounded Canvas fallback remains available if shader loading fails. In Appearance → Navigation appearance, blur strength ranges from 0 to 32 and surface opacity from 55% to 95%. Changes preview while dragging and persist on release. Zero disables blur. Rendering is clipped to the navigation capsule and uses the live backdrop.

- Custom springs and the backdrop share one VSync ticker. Only active springs advance; iteration snapshots are rebuilt when the set changes. Material components and routes retain Flutter's animation lifecycles.
- Analytic springs preserve position and velocity when retargeted and advance by elapsed time on long frames. Resuming resets the time baseline so background time does not enter transitions.
- Rust generates a 32×32 RGBA parameter atlas (4 KiB of raw data) from a persisted installation seed. It controls position, depth, magnitude, tint and independent evolution scales. The atlas and shader load before the first frame and remain shared; no per-frame Rust calls are made. Quintic noise changes brightness on a 64–160 second base scale and drift on a 240–600 second base scale, with at most 1.2 logical pixels of displacement per axis. There is no 12-second time reset. Empty sky skips noise evaluation.
- Routes share one backdrop updated through `CustomPainter.repaint`. Inactive tabs release their elements after the exit animation. Ambient stars and avatar morphs share a clock capped at 30 updates per second; interaction springs follow display VSync. Android controls the final display mode through settings, power and thermal policy.
- Shape caching is limited to 64 pairs. Memory pressure clears shapes and evictable images. Attachment reads grow on demand and reject oversized input rather than truncating it.
- System reduced motion and power-saving freeze the current sky, then resume from the same phase. AMOLED retains faint stars on a black background without the broad colored glow.

These mechanisms do not establish measured power savings or sustained 120 FPS. Performance claims require profile-mode device measurements.

## Colors and resources

Reference colors come from process-CMYK simulation patches in the supplied coated-color PDF; see [palette provenance](assets/palettes/coated_reference.json). The six colors are 3295 C `#00907F`, 2725 C `#4D5FAB`, 3015 C `#007CB7`, 1665 C `#F37121`, 2587 C `#6352A2` and Cool Gray 11 C `#5A5B5E`. Surfaces and state colors are derived; Monet uses system tones. RGB output is not a certified physical Pantone spot-color match.

Font origins/hashes are in the [font manifest](assets/fonts/manifest.json), with notices in [assets/licenses](assets/licenses). Translations live in `assets/l10n`; application comments are English. All 121 TXT files under `rust/resources` are referenced, totaling 1,958 bytes: 37 runtime keyword files and the remaining test resources. `include_str!` embeds text at compile time, not through per-file reads during animation. Do not delete these dependencies.

## Structure

| Directory | Responsibility |
| --- | --- |
| `lib/aurora` | Scheduling, springs, shapes, themes and components |
| `lib/messaging` | Conversations, codes, composer, MMS, trash and state |
| `lib/settings`, `lib/sync` | Settings and sync client |
| `android/app/src/main/kotlin` | Roles, Telephony, notifications, SIMs, permissions and scheduling |
| `rust/src` | Segmentation, analysis, search, MMS codecs, crypto and bridge APIs |
| `server-rs` | Optional sync service |
| `test`, `integration_test`, `tool` | Regression/device tests, builds and verification |

Application logic uses Dart, Kotlin and Rust; generated Java plugin registration is a Flutter toolchain artifact. Android providers hold carrier messages; app storage holds archive, trash and scheduling state. Internal SMS/MMS IDs are positive/negative and converted back to provider IDs at the platform boundary.

## Build and verify

Pinned environment: Flutter 3.47.9 / Dart 3.13.7, JDK 17, Android SDK 36, Rust 1.99.1 and FRB 2.13.0. Flutter Gradle configuration selects the NDK; CI versions are in the [Android workflow](.github/workflows/android-delivery.yml). Install SDK/NDK and Rust Android targets first. Initial dependency resolution requires network access.

```powershell
flutter pub get --enforce-lockfile
flutter analyze
flutter test
dart run tool/check_localization.dart
python tool/generate_android_strings.py --check
python tool/check_sms_contract.py
cargo test --locked --manifest-path rust/Cargo.toml
cargo test --locked --manifest-path server-rs/Cargo.toml
flutter build apk --profile
python tool/verify_android_pages.py build/app/outputs/flutter-apk/app-profile.apk
```

Run `./gradlew testDebugUnitTest lintDebug` from `android` for native checks; use `gradlew.bat` on Windows. For Windows `PropertyEscape` lint errors, inspect generated `local.properties`: escape drive colons as `C\:` and backslashes as `\\`, then rerun affected lint tasks.

GitHub Actions uses `tool/setup_android_sdk.sh` to locate command-line tools through `ANDROID_HOME` (or `ANDROID_SDK_ROOT`), invoke `sdkmanager` by absolute path and install pinned SDK/NDK packages. It does not rely on the runner's default PATH. The SDK must contain `cmdline-tools/latest/bin/sdkmanager`. Test and lint reports are preserved as a separate artifact on failure; early toolchain failures may not produce reports yet.

Flutter is checked out at a pinned commit with `fetch-depth: 0` to retain release tags and history. Before dependency resolution, `tool/check_flutter_sdk.py` verifies HEAD, the release tag and machine-readable Flutter/Dart versions. Resolve `0.0.0-unknown` by repairing SDK tags or checkout state, rather than fabricating version files, removing constraints or blindly upgrading dependencies. Actual SDK metadata is retained in the validation artifact.

Profile output is `build/app/outputs/flutter-apk/app-profile.apk`, signed with a development key. Use `flutter build apk --debug` for debugging. Run `flutter_rust_bridge_codegen generate` after bridge interface changes, not on every build.

### Device performance and compatibility

```powershell
$env:ORG_GRADLE_PROJECT_qingniaoBenchmark = 'true'
flutter drive --profile --driver=test_driver/interface_cadence_driver.dart --target=integration_test/interface_cadence_test.dart -d DEVICE_ID
Remove-Item Env:ORG_GRADLE_PROJECT_qingniaoBenchmark
```

This uses isolated package `com.blue.qingniao.benchmark`, fixed fixtures and no SMS permissions. Results go to `build/verification/device-interface-cadence.json`. It overwrites default profile output; rebuild the normal app before delivery.

The 16 KB tool checks ARM64/x86-64 ELF and APK library alignment. Android SDK's `zipalign -c -P 16 4 APK_PATH` provides another packaging check. Alignment success is not runtime validation on a 16 KB system.

Acceptance covers role listings, dual SIM, multipart receipts, carrier MMS, reboot/background restrictions, scheduling, deletion/restore, RTL/large fonts and reduced motion. Historical OnePlus results do not establish compatibility across all OPPO, Xiaomi or other ROMs. Frame timings, 16 KB runtime and the full carrier matrix still require verification.

### Production signing

Keep keys outside the repository. Securely inject `QINGNIAO_KEYSTORE_PATH`, `QINGNIAO_STORE_PASSWORD`, `QINGNIAO_KEY_ALIAS` and `QINGNIAO_KEY_PASSWORD`. Production builds fail without credentials instead of using debug signing.

```powershell
flutter build apk --release
flutter build appbundle --release
```

Increment the version code in `pubspec.yaml` before release and verify the final certificate, SHA-256 and artifact. Signature mismatch or downgrade prevents updating; do not uninstall to bypass checks and lose app state. CI supports verification artifacts and manually requested Release drafts; see the workflow. Pinned dependencies do not alone prove bit-for-bit reproducibility.

## Optional sync and FCM

Build with `cargo build --release --locked --manifest-path server-rs/Cargo.toml`. Run `qingniao-sync --bind 127.0.0.1:8787 --data /path/to/data.json` behind an HTTPS reverse proxy and restrict registration. Routes are defined in the [server source](server-rs/src/main.rs); the client is in the [sync engine](lib/sync/sync_engine.dart). Device tokens are credentials and must not appear in logs or public configuration.

Sync runs on foreground startup/resume and periodic foreground checks; MMS attachments are outside its current scope. The server sees device metadata, public keys, routing, ciphertext sizes and timing. Version-1 envelopes use X25519, HKDF-SHA256 and AES-256-GCM but lack independent sender authentication. Private keys are not yet wrapped by Android Keystore; public-key trust binding needs validation. This does not establish full impersonation resistance against a malicious server or audited-messenger security equivalence.

Rust P2P provides a Noise-based authenticated session layer requiring trusted peer-key binding. Discovery, Wi-Fi Direct and a user-facing sending workflow are not integrated. Ordinary SMS/MMS does not automatically gain end-to-end encryption. RCS and Xiaobu AI/NPU are not integrated.

FCM setup:

1. Register `com.blue.qingniao` in a real Firebase project and obtain `google-services.json`.
2. Import the file in Settings → Network push, review the fields and save. Manual entry accepts the project ID, project number, Android app ID and public API key. Imports are limited to 128 KiB and must match the package and project number; service-account keys are rejected. The first configuration initializes immediately. To switch an existing SDK project, disable push first, save, then force-stop and reopen the app. Publishers can still generate bundled resources with `python tool/configure_firebase.py android/app/google-services.json` and rebuild.
3. With Google Play services and Firebase connectivity, enable network push, pair sync and copy the FID push identifier.
4. On a trusted sender, install `google-auth` and `requests`, configure Application Default Credentials with FCM send permission, then run `tool/send_sync_push.py --project PROJECT_ID --space-id SPACE_ID --installation-id-file PRIVATE_FILE`.

Payloads contain only `type=sync_available` and the matching `spaceId`, never SMS bodies. Foreground delivery triggers sync; background delivery shows a generic notification that opens the app for synchronization. The server does not automatically register FIDs; update changed identifiers. Live registration/delivery requires a real Firebase project. A proxy does not convert carrier SMS into FCM.

Saving validates the configuration format, not project connectivity. Push is marked enabled only after successful SDK registration. Configuration lives in private app storage with backup disabled. New configuration labels are translated into Chinese and English; other locales currently use English fallback.

## Maintenance and license

Local evidence lives under `build/verification` and applies only to the corresponding source and artifact. Implementation, device validation and security review are distinct evidence levels. There is no zero-defect or universal-device guarantee.

Licensed under [PolyForm Small Business License 1.0.0](LICENSE). Fonts and dependencies retain their respective licenses; review their terms before redistribution.
