# samsung_iap_example

A restore-spike screen (`lib/main.dart`) that drives `SamsungIapPlatform` directly: switch the
operation mode, query products, buy, complete, restore, and log every update together with the
SDK's raw purchase JSON. Results of the November 2026 run are in
[../docs/restore-spike-2026-11.md](../docs/restore-spike-2026-11.md).

Samsung IAP checks the app's registered package and signing key, so as checked in the example
only works for the project owner:

- `applicationId` is `com.asol.safedrive` (`android/app/build.gradle.kts`);
- it signs with the registered key from `android/key.properties` (gitignored, never
  committed). Without that file it falls back to the debug key, and Samsung rejects the calls.

To run it yourself, substitute your own Seller Portal package name and signing key, and replace
the product ids at the top of `lib/main.dart` with your own items.
