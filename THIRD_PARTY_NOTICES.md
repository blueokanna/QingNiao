# Third-party dependencies

Application-owned Android code is Kotlin. Flutter's tooling may generate Java plugin registration files; these are build integration output, not migrated application code.

- Flutter and Dart provide UI, platform channels and application tooling under their upstream licenses.
- flutter_rust_bridge 2.13.0 provides Rust/Dart bindings under the MIT license.
- com.klinkerapps:android-smsmms:5.2.6 supplies MMS PDU parsing, composition and persistence derived from AOSP, under Apache License 2.0.
- com.klinkerapps:logger:1.0.3 is a compatibility dependency of the MMS library, under Apache License 2.0.

The MMS dependency contains JVM library code; it is not a Kotlin rewrite of the upstream library. Source and license information: https://github.com/klinker41/android-smsmms.

CapsuleSMS was inspected to identify migration requirements. Its Java application sources were not copied into this repository. The current implementation does not claim complete feature parity with that application.
