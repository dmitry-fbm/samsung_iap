import 'package:flutter_test/flutter_test.dart';
import 'package:samsung_iap/samsung_iap.dart';
import 'package:samsung_iap/samsung_iap_platform_interface.dart';
import 'package:samsung_iap/samsung_iap_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockSamsungIapPlatform
    with MockPlatformInterfaceMixin
    implements SamsungIapPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final SamsungIapPlatform initialPlatform = SamsungIapPlatform.instance;

  test('$MethodChannelSamsungIap is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelSamsungIap>());
  });

  test('getPlatformVersion', () async {
    SamsungIap samsungIapPlugin = SamsungIap();
    MockSamsungIapPlatform fakePlatform = MockSamsungIapPlatform();
    SamsungIapPlatform.instance = fakePlatform;

    expect(await samsungIapPlugin.getPlatformVersion(), '42');
  });
}
