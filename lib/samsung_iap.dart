
import 'samsung_iap_platform_interface.dart';

class SamsungIap {
  Future<String?> getPlatformVersion() {
    return SamsungIapPlatform.instance.getPlatformVersion();
  }
}
