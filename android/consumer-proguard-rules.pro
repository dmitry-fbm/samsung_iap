# Samsung IAP SDK (AIDL service + helper classes are reached reflectively / via Binder).
-keep class com.samsung.android.sdk.iap.lib.** { *; }
-keep class com.samsung.android.iap.** { *; }
-dontwarn com.samsung.android.sdk.iap.lib.**
-dontwarn com.samsung.android.iap.**
