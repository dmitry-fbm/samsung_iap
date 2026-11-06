import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'samsung_iap_platform_interface.dart';

/// An implementation of [SamsungIapPlatform] that uses method channels.
class MethodChannelSamsungIap extends SamsungIapPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('samsung_iap');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
