# samsung_iap

Android-only Flutter plugin implementing `in_app_purchase_platform_interface` over the
Samsung IAP SDK 6.5.2 for Galaxy Store builds. The app constructs and uses the platform
directly (no `dartPluginClass`). Requires Android minSdk 31, Dart `^3.13.0`.

## Samsung IAP SDK

The SDK is resolved from Maven Central as `com.samsung.developer:iap:6.5.2`, published by
Samsung under the Samsung IAP License Agreement
(https://developer.samsung.com/iap/terms/license-agreement.txt) and Apache-2.0 (per its POM).
No AAR is committed to this repo or needs to be downloaded by hand.

## Usage

**Never call `InAppPurchase.instance` in a Galaxy build.** In `in_app_purchase` 3.3.x its
getter calls `InAppPurchaseAndroidPlatform.registerPlatform()` on Android, which silently
replaces this platform and connects Google Play billing. Construct `SamsungIapPlatform` and
use it directly, one instance per app:

```dart
final iap = SamsungIapPlatform(mode: SamsungIapMode.production);
iap.purchaseStream.listen((purchases) async {
  for (final p in purchases) {
    // Grant/verify (purchaseID → your backend), then acknowledge:
    if (p.pendingCompletePurchase) await iap.completePurchase(p);
  }
});
await iap.restorePurchases(); // at startup
final products = await iap.queryProductDetails({'my.item'});
await iap.buyNonConsumable(
  purchaseParam: PurchaseParam(productDetails: products.productDetails.first),
);
```

- **Restore at startup.** Call `restorePurchases()` when the app starts, and
  `completePurchase` every restored purchase with `pendingCompletePurchase == true`. Nothing
  else delivers unacknowledged purchases (for example after a crash between payment and
  acknowledge).
- **Errors.**
  - A cancelled payment arrives as `PurchaseStatus.canceled` with no error.
  - `SamsungIapPlatform.samsungAlreadyOwned` (-1003) arrives as `PurchaseStatus.error` with
    code `'-1003'`. Treat the item as owned and run `restorePurchases()`.
  - Other payment failures arrive as `PurchaseStatus.error` with the Samsung error code.
  - Non-payment calls throw `PlatformException(code: <Samsung errorCode>)`; for example
    `restorePurchases()` rethrows it. `queryProductDetails` returns it as the response's
    `error`.
- **Entitlement comes from your backend.** `restorePurchases()` returns every owned
  purchase, including subscriptions past their end date: Galaxy Store's owned list lags
  expiry and cancellation.
- **`isAvailable()`** only checks that Galaxy Store is installed and enabled. It can be true
  while store calls fail with -1000 (for example when Galaxy Store is outdated).
- **Manifest.** The plugin's Android manifest adds the permission
  `com.samsung.android.iap.permission.BILLING` and a `<queries>` entry for Galaxy Store
  (`com.sec.android.app.samsungapps`) to **every** flavour of the consuming app. In flavours
  that ship to other stores, remove the permission in that flavour's manifest:

  ```xml
  <uses-permission android:name="com.samsung.android.iap.permission.BILLING"
      tools:node="remove" />
  ```

- **Sandbox (`SamsungIapMode.test`).** Licence testers' item purchases are voided about
  10 minutes after purchase, and sandbox subscriptions run for short periods (10–20 min) and
  renew under the same purchase id. See [docs/restore-spike-2026-11.md](docs/restore-spike-2026-11.md).
