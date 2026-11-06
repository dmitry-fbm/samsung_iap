import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'samsung_iap_method_channel.dart';

abstract class SamsungIapPlatform extends PlatformInterface {
  /// Constructs a SamsungIapPlatform.
  SamsungIapPlatform() : super(token: _token);

  static final Object _token = Object();

  static SamsungIapPlatform _instance = MethodChannelSamsungIap();

  /// The default instance of [SamsungIapPlatform] to use.
  ///
  /// Defaults to [MethodChannelSamsungIap].
  static SamsungIapPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [SamsungIapPlatform] when
  /// they register themselves.
  static set instance(SamsungIapPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
