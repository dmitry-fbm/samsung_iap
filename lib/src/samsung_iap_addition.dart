import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';

import 'purchase_mapping.dart';
import 'samsung_iap_platform.dart';
import 'types.dart';

/// Samsung-only calls, reached through
/// `InAppPurchasePlatformAddition.instance`. Shares the host API and
/// operation mode of the [SamsungIapPlatform] that created it.
class SamsungIapPlatformAddition extends InAppPurchasePlatformAddition {
  SamsungIapPlatformAddition(this._platform);

  final SamsungIapPlatform _platform;

  /// Raw JSON from the SDK's promotion eligibility check for [itemIds].
  /// A host failure propagates as a `PlatformException`.
  Future<String> getPromotionEligibility(Set<String> itemIds) async =>
      (await _platform.readyHostApi()).getPromotionEligibility(
        itemIds.join(','),
      );

  /// Changes a subscription from [oldItemId] to [newItemId] with
  /// [prorationMode] (the SDK's mode name, passed through).
  ///
  /// Throws [InAppPurchaseException] with source `samsung_iap` when the
  /// change fails or is cancelled: the code is the SDK's error code (a
  /// cancel is [SamsungIapPlatform.samsungPaymentCanceled]), or `no_result`
  /// when the host returned neither a purchase nor an error.
  Future<SamsungPurchaseDetails> changeSubscriptionPlan({
    required String oldItemId,
    required String newItemId,
    required String prorationMode,
  }) async {
    final api = await _platform.readyHostApi();
    final result = await api.changeSubscriptionPlan(
      oldItemId,
      newItemId,
      prorationMode,
    );
    final purchase = result.purchase;
    if (purchase != null) {
      return samsungPurchaseDetails(purchase, PurchaseStatus.purchased);
    }
    final error = result.error;
    throw InAppPurchaseException(
      source: samsungIapSource,
      code: error == null ? 'no_result' : '${error.code}',
      message: error?.message ?? 'Plan change returned no result',
    );
  }
}
