import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:samsung_iap/samsung_iap.dart';

class _Host extends SamsungIapHostApi {
  final calls = <String>[];
  PurchaseResultMsg planResult = PurchaseResultMsg();
  bool failEligibility = false;

  @override
  Future<void> setOperationMode(String mode) async =>
      calls.add('setOperationMode:$mode');

  @override
  Future<String> getPromotionEligibility(String itemIdsCsv) async {
    calls.add('getPromotionEligibility:$itemIdsCsv');
    if (failEligibility) throw PlatformException(code: '-1002');
    return '{"ok":true}';
  }

  @override
  Future<PurchaseResultMsg> changeSubscriptionPlan(
    String oldItemId,
    String newItemId,
    String prorationMode,
  ) async {
    calls.add('changeSubscriptionPlan:$oldItemId:$newItemId:$prorationMode');
    return planResult;
  }
}

PurchaseMsg _purchase() => PurchaseMsg(
  itemId: 'new',
  purchaseId: 'P1',
  paymentId: 'PAY',
  orderId: 'ORD',
  purchaseDate: '2026-11-01 10:00:00',
  type: 'subscription',
  acknowledged: false,
  jsonString: '{}',
);

Future<SamsungPurchaseDetails> _change(SamsungIapPlatformAddition a) =>
    a.changeSubscriptionPlan(oldItemId: 'o', newItemId: 'n', prorationMode: 'm');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Host host;
  late SamsungIapPlatformAddition addition;

  setUp(() {
    host = _Host();
    SamsungIapPlatform(api: host);
    addition =
        InAppPurchasePlatformAddition.instance! as SamsungIapPlatformAddition;
  });

  test('constructing a platform installs the addition', () {
    expect(
      InAppPurchasePlatformAddition.instance,
      isA<SamsungIapPlatformAddition>(),
    );
  });

  test('changeSubscriptionPlan forwards ids and proration', () async {
    host.planResult = PurchaseResultMsg(purchase: _purchase());
    final details = await addition.changeSubscriptionPlan(
      oldItemId: 'old',
      newItemId: 'new',
      prorationMode: 'INSTANT_PRORATED_DATE',
    );
    expect(host.calls, [
      'setOperationMode:production',
      'changeSubscriptionPlan:old:new:INSTANT_PRORATED_DATE',
    ]);
    expect(details.productID, 'new');
    expect(details.purchaseID, 'P1');
    expect(details.status, PurchaseStatus.purchased);
    expect(details.pendingCompletePurchase, isTrue);
  });

  test('changeSubscriptionPlan throws on error and on cancel', () async {
    host.planResult = PurchaseResultMsg(
      error: ErrorMsg(code: 1, message: 'cancelled'),
    );
    await expectLater(
      _change(addition),
      throwsA(
        isA<InAppPurchaseException>()
            .having((e) => e.source, 'source', 'samsung_iap')
            .having((e) => e.code, 'code', '1'),
      ),
    );
    host.planResult = PurchaseResultMsg();
    await expectLater(
      _change(addition),
      throwsA(
        isA<InAppPurchaseException>().having(
          (e) => e.code,
          'code',
          'no_result',
        ),
      ),
    );
  });

  test('promotion eligibility joins ids with commas', () async {
    final json = await addition.getPromotionEligibility({'a', 'b'});
    expect(json, '{"ok":true}');
    expect(host.calls.last, 'getPromotionEligibility:a,b');
  });

  test('promotion eligibility propagates PlatformException', () async {
    host.failEligibility = true;
    await expectLater(
      addition.getPromotionEligibility({'a'}),
      throwsA(isA<PlatformException>()),
    );
  });
}
