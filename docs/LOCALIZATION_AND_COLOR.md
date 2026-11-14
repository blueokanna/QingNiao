# Android color, localization and native-page verification

The application targets Android only, with package `com.blue.qingniao`, minimum API 31 and target API 36.

## Color provenance

The six reference colors come from the supplied 19-page coated-color PDF. Its SHA-256 is `88200b809cfe4cadd2d135c97cad497967789a11e1f89b5b3726f2fa11960fef`. The document itself describes process-CMYK simulations; neither the PDF nor an RGB screen establishes a certified physical spot-color match.

| Reference | PDF page | Printed CMYK percentages | Extracted RGB |
| --- | ---: | --- | --- |
| PANTONE 3295 C | 8 | 100 / 0 / 56 / 18 | `#00907F` |
| PANTONE 2725 C | 6 | 79 / 69 / 0 / 0 | `#4D5FAB` |
| PANTONE 3015 C | 7 | 100 / 23 / 0 / 18 | `#007CB7` |
| PANTONE 1665 C | 3 | 0 / 69 / 100 / 0 | `#F37121` |
| PANTONE 2587 C | 5 | 72 / 79 / 0 / 0 | `#6352A2` |
| PANTONE Cool Gray 11 C | 11 | 0 / 0 / 0 / 79 | `#5A5B5E` |

`tool/extract_reference_palette.py` reads the vector fill next to each selected identifier and converts its PDF color space through PyMuPDF 1.28.2. `assets/palettes/coated_reference.json` retains the source hash, page, CMYK label and conversion result. The original PDF is not packaged in the application.

Reference mode uses those exact RGB values for swatches and the primary color. Material tonal surfaces, state layers and decorative effects are derived colors. On-primary text chooses black or white for at least 4.5:1 contrast. Wallpaper colors remain an explicit Monet option; AMOLED mode retains its black surfaces. Existing saved palette names are migrated when settings load.

The inbox removes the repeated brand strip, engine diagnostics, category badges and redundant per-row counts. Search, filters, sender, preview, time, unread state, SIM and code-copy actions remain available.

## Language resources

The ten language catalogs are English, Simplified Chinese, Hindi, Spanish, Arabic, French, Bengali, Portuguese, Russian and Urdu. Each contains 446 entries. The language choice persists, with system preference resolution and an English fallback for unsupported languages. Dates use the selected language; Arabic and Urdu use RTL layout.

Application-owned Dart, Kotlin and Rust sources use English comments and contain no literal Han characters. Translations, native keyword dictionaries and multilingual Rust text fixtures live in resources. Test repositories remain under `test/support/` and are not imported by the application.

`tool/check_localization.dart` rejects missing catalog entries, mismatched placeholders, unregistered literal translation calls and Han characters in application source. `tool/generate_android_strings.py` derives notification resources from the same catalogs; `--check` detects stale generated XML. Both checks run in Android delivery CI. Catalog completeness is a structural check, not native-speaker linguistic certification. Carrier-provided content and underlying platform exception details are not translated by these catalogs.

## Native build integrity

Android Rust linking explicitly sets `max-page-size=16384` and `common-page-size=16384`. `tool/verify_android_pages.py` checks all packaged ARM64 and x86-64 libraries for ELF LOAD alignment, offset congruence, RELRO boundaries, uncompressed storage and APK data alignment. Android `zipalign -c -P 16 4` provides a separate packaging check.

The Windows Cargokit launcher now propagates dependency-resolution, compilation and runner failures. This fixes a verified failure where Rust compilation failed but Gradle still packaged cached libraries. A negative build probe confirmed that a real native compilation error now stops `assembleDebug` with exit code 1.

The upgraded AES-GCM, HKDF, X25519 and rand APIs are supported without rolling back the parallel dependency updates. Key and nonce generation fail closed if OS randomness is unavailable. An interoperability fixture generated with the previous dependency versions verifies that existing version-1 envelopes still decrypt. This does not add sender authentication to that envelope format or constitute a cryptographic audit.

## Verification evidence

The completed checks include 63 Flutter tests, 11 Kotlin tests, 84 Rust core tests and 4 sync-server tests. Layout checks cover the inbox, verification codes and appearance pages in all ten languages at 360 logical pixels and 1.4 text scaling. Palette tests compare every primary with the extracted PDF values and check on-primary contrast. Dart static analysis is clean. Android lint completes without errors; style and platform warnings remain recorded in its report.

Delivery evidence is under `build/verification/`: `qingniao-local-services-profile.apk`, SHA-256, source-input hashes, signature report, native-page report and build/test logs. The profile APK is signed with the Android debug certificate. Production signing still requires the configured release credentials. Direct Gradle invocations resolve the Flutter SDK from the same project and local properties as Flutter, so native checks do not depend on a shell-specific `FLUTTER_ROOT` value.

The previously connected PLK110 reported API 37 and a 4096-byte kernel page size. It disconnected before the isolated frame-timing benchmark began. The host has no configured emulator hypervisor and no installed 16 KB image. Consequently, binary alignment is verified, while measured device frame timings, 16 KB runtime execution, the full OEM/carrier MMS matrix and an independent security audit remain outstanding. No zero-defect or universal device-compatibility claim is made.

Google's current [target API requirement](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en) requires API 36 for new phone apps and updates. Its [16 KB guidance](https://developer.android.com/guide/practices/page-sizes) requires compatible native binaries and recommends runtime testing. Matching these technical settings does not by itself establish Play policy approval.
