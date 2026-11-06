import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';

import 'messages.g.dart';

/// Samsung IAP operation mode (`IapHelper.setOperationMode`).
enum SamsungIapMode {
  /// Real payments.
  production('production'),

  /// Sandbox: every payment succeeds.
  test('test'),

  /// Sandbox: every payment fails.
  testFailure('test_failure');

  const SamsungIapMode(this.wire);

  /// The value sent to the host.
  final String wire;
}

/// A Galaxy Store product, carrying the raw host message.
class SamsungProductDetails extends ProductDetails {
  SamsungProductDetails(this.raw)
    : isSubscription = raw.type == 'subscription',
      super(
        id: raw.itemId,
        title: raw.itemName,
        description: raw.itemDesc,
        price: raw.itemPriceString,
        rawPrice: raw.itemPrice,
        currencyCode: raw.currencyCode,
      );

  final ProductMsg raw;
  final bool isSubscription;
}

/// A Galaxy Store purchase update. [raw] is null for updates that carry no
/// Samsung purchase (pending, canceled, error).
class SamsungPurchaseDetails extends PurchaseDetails {
  SamsungPurchaseDetails({
    required super.productID,
    required super.verificationData,
    required super.status,
    super.purchaseID,
    super.transactionDate,
    this.raw,
  });

  final PurchaseMsg? raw;
}

/// Purchase parameters with Samsung's obfuscated account/profile ids.
class SamsungPurchaseParam extends PurchaseParam {
  SamsungPurchaseParam({
    required super.productDetails,
    super.applicationUserName,
    this.obfuscatedAccountId,
    this.obfuscatedProfileId,
  });

  final String? obfuscatedAccountId;
  final String? obfuscatedProfileId;
}
