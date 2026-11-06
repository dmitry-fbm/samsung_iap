import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:samsung_iap/samsung_iap.dart';

/// Records every host call in order; answers come from the public fields.
class FakeHostApi extends SamsungIapHostApi {
  final calls = <String>[];
  bool available = true;
  List<ProductMsg> products = [];
  List<PurchaseMsg> owned = [];
  PurchaseResultMsg paymentResult = PurchaseResultMsg();
  List<AckResultMsg>? ackResult;
  List<List<String>> acked = [];
  List<List<String>> consumed = [];
  int modeFailures = 0;
  int consumeStatus = 0;

  @override
  Future<bool> isAvailable() async {
    calls.add('isAvailable');
    return available;
  }

  @override
  Future<void> setOperationMode(String mode) async {
    calls.add('setOperationMode:$mode');
    if (modeFailures > 0) {
      modeFailures--;
      throw PlatformException(code: '-1000', message: 'not bound');
    }
  }

  @override
  Future<List<ProductMsg>> getProductsDetails(String itemIdsCsv) async {
    calls.add('getProductsDetails:$itemIdsCsv');
    return products;
  }

  @override
  Future<List<PurchaseMsg>> getOwnedList(String productType) async {
    calls.add('getOwnedList:$productType');
    return owned;
  }

  @override
  Future<PurchaseResultMsg> startPayment(
    String itemId,
    String? obfuscatedAccountId,
    String? obfuscatedProfileId,
  ) async {
    calls.add('startPayment:$itemId:$obfuscatedAccountId:$obfuscatedProfileId');
    return paymentResult;
  }

  @override
  Future<List<AckResultMsg>> acknowledgePurchases(
    List<String> purchaseIds,
  ) async {
    calls.add('acknowledgePurchases');
    acked.add(purchaseIds);
    return ackResult ??
        [
          for (final id in purchaseIds)
            AckResultMsg(purchaseId: id, statusCode: 0),
        ];
  }

  @override
  Future<List<AckResultMsg>> consumePurchasedItems(
    List<String> purchaseIds,
  ) async {
    calls.add('consumePurchasedItems');
    consumed.add(purchaseIds);
    return [
      for (final id in purchaseIds)
        AckResultMsg(purchaseId: id, statusCode: consumeStatus),
    ];
  }
}

ProductMsg _product(String id, {String type = 'subscription'}) => ProductMsg(
  itemId: id,
  itemName: 'SafeDrive 1 month',
  itemPriceString: '€2.99',
  itemPrice: 2.99,
  currencyCode: 'EUR',
  itemDesc: 'Unlimited driving',
  type: type,
);

PurchaseMsg _purchase({
  String itemId = 'online.as.safedrive.1m',
  String purchaseId = 'PID123',
  String type = 'subscription',
  bool acknowledged = false,
  String? subscriptionEndDate,
}) => PurchaseMsg(
  itemId: itemId,
  purchaseId: purchaseId,
  paymentId: 'PAY1',
  orderId: 'ORD1',
  purchaseDate: '2026-11-01 10:00:00',
  type: type,
  acknowledged: acknowledged,
  subscriptionEndDate: subscriptionEndDate,
  jsonString: '{"mPurchaseId":"$purchaseId"}',
);

PurchaseParam _param(String id) => PurchaseParam(productDetails: _details(id));

ProductDetails _details(String id) => ProductDetails(
  id: id,
  title: 't',
  description: 'd',
  price: '€2.99',
  rawPrice: 2.99,
  currencyCode: 'EUR',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeHostApi api;
  late SamsungIapPlatform platform;

  setUp(() {
    api = FakeHostApi();
    platform = SamsungIapPlatform(api: api);
  });

  test('is a valid InAppPurchasePlatform', () {
    InAppPurchasePlatform.instance = platform;
    expect(InAppPurchasePlatform.instance, same(platform));
  });

  test('query maps price and id', () async {
    api.products = [_product('online.as.safedrive.1m')];

    final response = await platform.queryProductDetails({
      'online.as.safedrive.1m',
      'unknown.id',
    });

    final product = response.productDetails.single;
    expect(product.id, 'online.as.safedrive.1m');
    expect(product.price, '€2.99');
    expect(product.rawPrice, 2.99);
    expect(product.currencyCode, 'EUR');
    expect(product, isA<SamsungProductDetails>());
    expect((product as SamsungProductDetails).isSubscription, isTrue);
    expect(response.notFoundIDs, ['unknown.id']);
    expect(response.error, isNull);
  });

  test('query maps a host failure to an error response', () async {
    final failing = _ThrowingHostApi(
      PlatformException(code: '-1001', message: 'network'),
    );
    final response = await SamsungIapPlatform(api: failing)
        .queryProductDetails({'a'});

    expect(response.productDetails, isEmpty);
    expect(response.notFoundIDs, ['a']);
    expect(response.error?.code, '-1001');
    expect(response.error?.source, 'samsung_iap');
  });

  test('buy emits pending then purchased', () async {
    api.paymentResult = PurchaseResultMsg(purchase: _purchase());
    final updates = platform.purchaseStream.take(2).toList();

    final started = await platform.buyNonConsumable(
      purchaseParam: _param('online.as.safedrive.1m'),
    );

    expect(started, isTrue);
    final lists = await updates;
    expect(lists[0].single.status, PurchaseStatus.pending);
    final purchased = lists[1].single;
    expect(purchased.status, PurchaseStatus.purchased);
    expect(purchased.productID, 'online.as.safedrive.1m');
    expect(purchased.purchaseID, 'PID123');
    expect(purchased.verificationData.serverVerificationData, 'PID123');
    expect(purchased.verificationData.source, 'samsung_iap');
    expect(
      purchased.verificationData.localVerificationData,
      '{"mPurchaseId":"PID123"}',
    );
    expect(purchased.pendingCompletePurchase, isTrue);
  });

  test('buy passes applicationUserName as obfuscatedAccountId', () async {
    api.paymentResult = PurchaseResultMsg(purchase: _purchase());
    final updates = platform.purchaseStream.take(2).toList();

    await platform.buyNonConsumable(
      purchaseParam: PurchaseParam(
        productDetails: _details('x'),
        applicationUserName: 'user-1',
      ),
    );
    await updates;

    expect(api.calls, contains('startPayment:x:user-1:null'));
  });

  test('buy uses SamsungPurchaseParam obfuscated ids', () async {
    api.paymentResult = PurchaseResultMsg(purchase: _purchase());
    final updates = platform.purchaseStream.take(2).toList();

    await platform.buyNonConsumable(
      purchaseParam: SamsungPurchaseParam(
        productDetails: _details('x'),
        obfuscatedAccountId: 'acc',
        obfuscatedProfileId: 'prof',
      ),
    );
    await updates;

    expect(api.calls, contains('startPayment:x:acc:prof'));
  });

  test('cancel maps to canceled', () async {
    api.paymentResult = PurchaseResultMsg(
      error: ErrorMsg(code: 1, message: 'canceled'),
    );
    final updates = platform.purchaseStream.take(2).toList();

    await platform.buyNonConsumable(purchaseParam: _param('x'));

    final last = (await updates)[1].single;
    expect(last.status, PurchaseStatus.canceled);
    expect(last.error, isNull);
  });

  test('already owned maps to error with code -1003', () async {
    api.paymentResult = PurchaseResultMsg(
      error: ErrorMsg(
        code: SamsungIapPlatform.samsungAlreadyOwned,
        message: 'Already purchased.',
      ),
    );
    final updates = platform.purchaseStream.take(2).toList();

    await platform.buyNonConsumable(purchaseParam: _param('x'));

    final last = (await updates)[1].single;
    expect(last.status, PurchaseStatus.error);
    expect(last.error?.code, '-1003');
  });

  test('other error maps to error', () async {
    api.paymentResult = PurchaseResultMsg(
      error: ErrorMsg(code: -1008, message: 'x'),
    );
    final updates = platform.purchaseStream.take(2).toList();

    await platform.buyNonConsumable(purchaseParam: _param('x'));

    final last = (await updates)[1].single;
    expect(last.status, PurchaseStatus.error);
    expect(last.error?.code, '-1008');
    expect(last.error?.source, 'samsung_iap');
    expect(last.error?.message, 'x');
  });

  test('thrown startPayment maps to error', () async {
    final failing = _ThrowingHostApi(
      PlatformException(code: '-1000', message: 'boom'),
    );
    final p = SamsungIapPlatform(api: failing);
    final updates = p.purchaseStream.take(2).toList();

    await p.buyNonConsumable(purchaseParam: _param('x'));

    final last = (await updates)[1].single;
    expect(last.status, PurchaseStatus.error);
    expect(last.error?.code, '-1000');
  });

  test('restore emits owned items and subscriptions as restored', () async {
    api.owned = [
      _purchase(
        itemId: 'online.as.safedrive.lifetime',
        purchaseId: 'L1',
        type: 'item',
        acknowledged: true,
      ),
      _purchase(purchaseId: 'S1', subscriptionEndDate: '2026-12-06 12:00:00'),
    ];
    final emissions = <List<PurchaseDetails>>[];
    final sub = platform.purchaseStream.listen(emissions.add);

    await platform.restorePurchases();
    await sub.cancel();

    expect(emissions, hasLength(1));
    expect(emissions.single, hasLength(2));
    expect(
      emissions.single.map((p) => p.status),
      everyElement(PurchaseStatus.restored),
    );
    expect(api.calls, contains('getOwnedList:all'));
  });

  test('restore emits subscriptions past their end date', () async {
    api.owned = [
      _purchase(purchaseId: 'OLD', subscriptionEndDate: '2000-01-01 00:00:00'),
    ];
    final emissions = <List<PurchaseDetails>>[];
    final sub = platform.purchaseStream.listen(emissions.add);

    await platform.restorePurchases();
    await sub.cancel();

    expect(emissions.single.single.purchaseID, 'OLD');
    expect(emissions.single.single.status, PurchaseStatus.restored);
  });

  test('restore emits subscription with unparseable end date', () async {
    api.owned = [_purchase(purchaseId: 'S1', subscriptionEndDate: 'garbage')];
    final emissions = <List<PurchaseDetails>>[];
    final sub = platform.purchaseStream.listen(emissions.add);

    await platform.restorePurchases();
    await sub.cancel();

    expect(emissions.single.single.purchaseID, 'S1');
  });

  test('restore emits empty list when nothing owned', () async {
    final emissions = <List<PurchaseDetails>>[];
    final sub = platform.purchaseStream.listen(emissions.add);

    await platform.restorePurchases();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(emissions, [isEmpty]);
  });

  test('restore emits before completing', () async {
    api.owned = [_purchase(type: 'item', acknowledged: true)];
    final received = <PurchaseDetails>[];
    final sub = platform.purchaseStream.listen(received.addAll);

    await platform.restorePurchases();
    final atReturn = received.length;
    await sub.cancel();

    expect(atReturn, 1);
  });

  test('restore rethrows host failure', () async {
    final failing = _ThrowingHostApi(
      PlatformException(code: '-1001', message: 'network'),
    );

    await expectLater(
      SamsungIapPlatform(api: failing).restorePurchases(),
      throwsA(isA<PlatformException>()),
    );
  });

  test('restored purchase pending-complete follows acknowledged', () async {
    api.owned = [
      _purchase(purchaseId: 'A', type: 'item'),
      _purchase(purchaseId: 'B', type: 'item', acknowledged: true),
    ];
    final emissions = <List<PurchaseDetails>>[];
    final sub = platform.purchaseStream.listen(emissions.add);

    await platform.restorePurchases();
    await sub.cancel();

    final byId = {for (final p in emissions.single) p.purchaseID: p};
    expect(byId['A']?.pendingCompletePurchase, isTrue);
    expect(byId['B']?.pendingCompletePurchase, isFalse);
  });

  Future<PurchaseDetails> restoredOne(PurchaseMsg msg) async {
    api.owned = [msg];
    final emissions = <List<PurchaseDetails>>[];
    final sub = platform.purchaseStream.listen(emissions.add);
    await platform.restorePurchases();
    await sub.cancel();
    api.calls.clear();
    return emissions.single.single;
  }

  test('complete acknowledges unacknowledged purchase', () async {
    final purchase = await restoredOne(_purchase(type: 'item'));

    await platform.completePurchase(purchase);

    expect(api.acked, [
      ['PID123'],
    ]);
    expect(api.consumed, isEmpty);
    expect(purchase.pendingCompletePurchase, isFalse);
  });

  test('complete on acknowledged purchase is a no-op', () async {
    final purchase = await restoredOne(
      _purchase(type: 'item', acknowledged: true),
    );

    await platform.completePurchase(purchase);

    expect(api.calls, isEmpty);
  });

  test('complete throws on ack failure', () async {
    final purchase = await restoredOne(_purchase(type: 'item'));
    api.ackResult = [
      AckResultMsg(purchaseId: 'PID123', statusCode: 1, statusString: 'fail'),
    ];

    await expectLater(
      platform.completePurchase(purchase),
      throwsA(isA<InAppPurchaseException>()),
    );
  });

  test('buyConsumable autoConsume consumes', () async {
    api.paymentResult = PurchaseResultMsg(
      purchase: _purchase(type: 'item', purchaseId: 'C1'),
    );
    final updates = platform.purchaseStream.take(2).toList();

    await platform.buyConsumable(purchaseParam: _param('x'));
    final last = (await updates)[1].single;

    expect(api.consumed, [
      ['C1'],
    ]);
    expect(
      api.calls.indexOf('consumePurchasedItems'),
      greaterThan(api.calls.indexWhere((c) => c.startsWith('startPayment'))),
    );
    expect(last.status, PurchaseStatus.purchased);
  });

  test('buyConsumable consume failure maps to error', () async {
    api
      ..consumeStatus = -1002
      ..paymentResult = PurchaseResultMsg(
        purchase: _purchase(type: 'item', purchaseId: 'C1'),
      );
    final updates = platform.purchaseStream.take(2).toList();

    await platform.buyConsumable(purchaseParam: _param('x'));
    final last = (await updates)[1].single;

    expect(last.status, PurchaseStatus.error);
    expect(last.error?.code, '-1002');
    expect(last.pendingCompletePurchase, isFalse);
    expect(last.purchaseID, 'C1');
  });

  test('listener may buy from its callback (no re-entrant add)', () async {
    api.paymentResult = PurchaseResultMsg(
      error: ErrorMsg(code: 1, message: 'canceled'),
    );
    final statuses = <PurchaseStatus>[];
    final retried = Completer<bool>();
    final sub = platform.purchaseStream.listen((list) {
      statuses.addAll(list.map((p) => p.status));
      if (list.single.status == PurchaseStatus.canceled &&
          !retried.isCompleted) {
        api.paymentResult = PurchaseResultMsg(purchase: _purchase());
        retried.complete(platform.buyNonConsumable(purchaseParam: _param('x')));
      }
    });

    await platform.buyNonConsumable(purchaseParam: _param('x'));
    expect(await retried.future, isTrue);
    await pumpEventQueue();
    await sub.cancel();

    expect(statuses, [
      PurchaseStatus.pending,
      PurchaseStatus.canceled,
      PurchaseStatus.pending,
      PurchaseStatus.purchased,
    ]);
  });

  test('listener may buy upon a restored list', () async {
    api.paymentResult = PurchaseResultMsg(purchase: _purchase());
    final statuses = <PurchaseStatus>[];
    Future<bool>? bought;
    final sub = platform.purchaseStream.listen((list) {
      statuses.addAll(list.map((p) => p.status));
      if (list.isEmpty) {
        bought = platform.buyNonConsumable(purchaseParam: _param('x'));
      }
    });

    await platform.restorePurchases();
    expect(await bought, isTrue);
    await pumpEventQueue();
    await sub.cancel();

    expect(statuses, [PurchaseStatus.pending, PurchaseStatus.purchased]);
  });

  test('mode failure is retried on the next call', () async {
    api.modeFailures = 1;
    final p = SamsungIapPlatform(mode: SamsungIapMode.test, api: api);

    expect(await p.isAvailable(), isFalse);
    expect(await p.isAvailable(), isTrue);

    expect(api.calls, [
      'setOperationMode:test',
      'setOperationMode:test',
      'isAvailable',
    ]);
  });

  test('isAvailable false when host says no store', () async {
    api.available = false;

    expect(await platform.isAvailable(), isFalse);
  });

  test('mode is applied before first call', () async {
    final p = SamsungIapPlatform(mode: SamsungIapMode.test, api: api);

    await p.isAvailable();
    await p.queryProductDetails({'a'});

    expect(api.calls.first, 'setOperationMode:test');
    expect(
      api.calls.where((c) => c.startsWith('setOperationMode')),
      hasLength(1),
    );
  });

  test('countryCode fails asynchronously', () async {
    final result = platform.countryCode();
    await expectLater(result, throwsUnimplementedError);
  });

  test('dispose closes the purchase stream', () async {
    final done = platform.purchaseStream.toList();
    await platform.dispose();
    expect(await done, isEmpty);
  });

  test('a payment finishing after dispose is dropped, not thrown', () async {
    api.paymentResult = PurchaseResultMsg(purchase: _purchase());
    await platform.buyNonConsumable(
      purchaseParam: _param('online.as.safedrive.1m'),
    );
    await platform.dispose();
    // Let the in-flight payment complete; an add-after-close would surface
    // here as an unhandled async error and fail the test.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  });
}

/// Throws [error] from every host call except setOperationMode.
class _ThrowingHostApi extends FakeHostApi {
  _ThrowingHostApi(this.error);

  final PlatformException error;

  @override
  Future<List<ProductMsg>> getProductsDetails(String itemIdsCsv) =>
      Future.error(error);

  @override
  Future<List<PurchaseMsg>> getOwnedList(String productType) =>
      Future.error(error);

  @override
  Future<PurchaseResultMsg> startPayment(
    String itemId,
    String? obfuscatedAccountId,
    String? obfuscatedProfileId,
  ) => Future.error(error);
}
