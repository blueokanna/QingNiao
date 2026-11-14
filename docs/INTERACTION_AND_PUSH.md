# Interaction, display cadence and network push

The application opens directly into the inbox. The former feature tour, startup animation and decorative header icons have been removed. When SMS access is missing, the inbox offers the default-role action without automatically opening a permission dialog.

## Message actions

The optional read-code recycling setting defaults to enabled. An incoming code that was unread when loaded is moved to recoverable trash only after its whole message bubble remains visible in the foreground conversation for approximately two seconds. Scrolling, backgrounding and selection interrupt this observation. Bulk marking messages read does not trigger recycling. The existing notification expiry only dismisses notifications; it does not delete message bodies.

Permanent deletion now verifies the provider when its delete operation reports zero affected rows. The local trash record is retained if deletion cannot be confirmed.

Scheduled alarms use the full database ID in their intent URI. Future tasks are restored after boot, package replacement and exact-alarm authorization. Missed tasks remain available for review instead of being sent together after a reboot. Without exact-alarm access, Android may delay the fallback alarm; force-stop and OEM background restrictions still require device validation.

Long-press a conversation to select it; tap additional conversations to extend the selection. The action menu copies complete message text, marks selected conversations read, or moves them into the existing recoverable trash. The toolbar also marks all SMS and MMS read, independently of the active search or filter. Back exits selection first.

Settings exposes separate physical left and right swipe actions. Left defaults to trash; right defaults to read. Archive, pin and disabled are also available. Physical direction remains consistent in Arabic and Urdu. Swipe backgrounds and rows share one clipping boundary. Tab navigation no longer competes for the same horizontal drag.

SMS provider IDs are positive; MMS identities use negative keys inside the application. Their original provider IDs are restored only at the provider boundary. The database migration updates existing MMS trash keys. Paging compares timestamp and identity across both providers, preventing duplicate IDs, skipped MMS and same-timestamp page overlap. Batch trash writes use a local transaction; new carrier messages arriving afterward remain visible.

Copied message text and push identifiers use Android's sensitive clipboard flag. Oversized copies fail with an explicit error instead of silently truncating text. SMS/MMS content never enters the FCM payload.

## Rendering

The Shape morph cache retains at most 64 ordered polygon pairs and uses pair equality instead of a combined hash as the cache key. System memory pressure clears this cache and evictable Flutter image entries. Attachment preview reads grow from an 8 KB buffer with an 8 MB limit; oversized input fails explicitly instead of silently returning truncated bytes. These changes bound allocations; no measured device-memory reduction is claimed.

The Rust resource audit found 121 referenced text files totaling 1,958 bytes. Of these, 37 are runtime classification keywords; the remaining files are test-only fixtures and assertion strings. `include_str!` embeds runtime strings at compile time, with no per-file reads during animation. Deleting these files would break their consumers. Test-only contents are excluded from normal application compilation.

Carrier RCS and OEM assistant integration remain outside the enabled capabilities. No carrier provisioning or OPPO partner SDK has been supplied. The application does not advertise network chat as RCS or claim that an NPU or Xiaobu model is in use.

Aurora publishes ambient updates on each Flutter VSync; the previous 15–30 Hz backdrop limiter is removed. Frame budgets use the active display's refresh rate. Quality adaptation reduces background complexity, not animation cadence. The power-saving option pauses ambient motion while retaining interaction springs. System reduced-motion preferences remain respected.

The application shares one backdrop across routes. `CustomPainter.repaint` invalidates its rendering without rebuilding the widget tree every frame. Retained tabs use retargetable springs and skip unvisited intermediate pages. Hidden pages stop their widget tickers and do not receive pointer events. Statistics and backup scans run on the Android message executor instead of the platform UI thread.

Android requests the active refresh rate and, on API 35+, the high frame-rate category. The system still controls the final display mode according to user settings, temperature and power policy. A request for 120 Hz is not proof of 120 rendered frames per second. See Android's [frame-rate guidance](https://developer.android.com/media/optimize/performance/frame-rate).

Navigation, menus, dropdowns, radio groups and progress indicators use the current Flutter Material 3 APIs. The three launcher designs share `assets/branding/launcher_geometry.json`, with separate adaptive foregrounds, API 33 monochrome layers, raster densities and 512 px assets. Their geometry follows Android's [adaptive icon canvas and safe-zone guidance](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive).

## Optional FCM configuration

FCM is disabled by default. A build without Firebase resources remains a working carrier SMS application, and the push settings page reports that it is not configured. Google Play services and access to Firebase endpoints are required. A proxy does not convert an operator SMS into an internet message.

1. Register an Android app with package `com.blue.qingniao` in a real Firebase project and download its public `google-services.json` configuration.
2. Run `python tool/configure_firebase.py android/app/google-services.json`, then rebuild. The generator validates the package and writes ignored Android resources. Do not place service-account keys in the application or repository.
3. Enable Network push in settings. The SDK uses the current `register`, `unregister` and `onRegistered` APIs with Firebase Installation IDs (FIDs), not the deprecated registration-token interface. See the [Firebase registration API](https://firebase.google.com/docs/reference/android/com/google/firebase/messaging/FirebaseMessaging).
4. Configure encrypted sync and pair the devices. Copy the push identifier and save it on the trusted sender together with the existing sync space ID. Refresh this registration when the FID changes; the current sync server does not automatically provision Firebase credentials or upload FIDs.
5. On the trusted sender, install `google-auth` and `requests`, configure Application Default Credentials with FCM send permission, then use `tool/send_sync_push.py --project PROJECT_ID --space-id SPACE_ID --installation-id-file PRIVATE_FILE`. It sends a real HTTP v1 request using the `fid` target. The [FCM message API](https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages) defines this target.

The accepted data payload has exactly two fields: `type=sync_available` and the paired `spaceId`. Other payloads, stale messages, future timestamps and duplicate message IDs are rejected. The foreground app synchronizes through its existing encrypted sync engine. In the background, FCM posts a generic notification that opens the app for synchronization. It does not perform unattended headless SMS import, inject received data as carrier SMS, or send SMS on the user's behalf. Notification-style FCM payloads are outside this contract; use the supplied data-only sender.

No Firebase project was supplied for this revision, so live registration and internet delivery have not been verified.

## Verification

The regression suite covers initial entry, retained tabs, rapid retargeting, multi-selection, copying, read-all, disabled gestures, physical swipe direction in RTL, large text and all ten language catalogs. Native tests cover provider identity collisions, pagination boundaries and push payload validation. The manifest check verifies the default SMS activity, service, receiver permissions and URI schemes.

`integration_test/interface_cadence_test.dart` uses 164 local fixture conversations in an isolated `com.blue.qingniao.benchmark` package. Run with `ORG_GRADLE_PROJECT_qingniaoBenchmark=true` and `flutter drive --profile --driver=test_driver/interface_cadence_driver.dart --target=integration_test/interface_cadence_test.dart -d DEVICE_ID`. Its report contains measured frame timings and the display refresh rate. This package does not replace the real app or request SMS access. A physical device must remain connected for this check; a disconnected run is not a performance result.

Final build, test, native-page, signature and input-hash evidence is stored under `build/verification/`. Profile APKs are for performance testing and use development signing. Production releases still require the configured production signing credentials.
