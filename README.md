# samsung_iap

Android-only Flutter plugin implementing `in_app_purchase_platform_interface` over the
Samsung IAP SDK 6.5.2 for Galaxy Store builds. The app registers it explicitly
(no `dartPluginClass`). Requires Android minSdk 31, Dart `^3.13.0`.

## Samsung IAP SDK

The SDK is resolved from Maven Central as `com.samsung.developer:iap:6.5.2`, published by
Samsung under the Samsung IAP License Agreement
(https://developer.samsung.com/iap/terms/license-agreement.txt) and Apache-2.0 (per its POM).
No AAR is committed to this repo or needs to be downloaded by hand.
