# samsung_iap

Android-only Flutter plugin implementing `in_app_purchase_platform_interface` over the
Samsung IAP SDK (6.5.x) for Galaxy Store builds. The app registers it explicitly
(no `dartPluginClass`). Requires Android minSdk 31, Dart `^3.13.0`.

## Samsung SDK licence / AAR

The Samsung IAP SDK is downloaded from https://developer.samsung.com/iap/download.html,
which requires a Samsung developer account login. Its licence terms could not be read
without that login, so redistribution in this public repo is assumed NOT allowed:
`android/libs-repo/` is gitignored and the AAR is not committed.

One-time drop-in (per checkout):

1. Sign in and download the IAP SDK 6.5.x package from the page above.
2. Place the AAR at `android/libs-repo/com/samsung/android/iap/iap-sdk/6.5.0/iap-sdk-6.5.0.aar`.
3. Create a sibling `iap-sdk-6.5.0.pom` (groupId `com.samsung.android.iap`, artifactId
   `iap-sdk`, version `6.5.0`, packaging `aar`):

```xml
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.samsung.android.iap</groupId>
  <artifactId>iap-sdk</artifactId>
  <version>6.5.0</version>
  <packaging>aar</packaging>
</project>
```

If the downloaded version differs, update the version in `android/build.gradle.kts` and the path.
