package online.`as`.samsung_iap

import android.app.Activity

/**
 * Stub [SamsungIapHostApi]: every method fails cleanly until the Samsung IAP SDK AAR is present
 * and Task 2b implements this class over `IapHelper`. Deliberately references no Samsung SDK class.
 *
 * Error contract for the real implementation (controller ruling):
 *  - Non-payment calls (getProductsDetails, getOwnedList, acknowledgePurchases,
 *    consumePurchasedItems, getPromotionEligibility) report failure by completing the callback with
 *    `Result.failure(FlutterError(code = <Samsung errorCode as string>, message = <errorString>))`.
 *  - Payment calls (startPayment, changeSubscriptionPlan) NEVER fail the callback: errors are
 *    returned as `ErrorMsg` inside `PurchaseResultMsg` so Dart can map cancel to `canceled`.
 *    (No activity: `ErrorMsg(code = -1, message = "no activity")`.)
 */
class IapHostApiImpl(private val activityProvider: () -> Activity?) : SamsungIapHostApi {

  private fun notImplemented() = FlutterError("not_implemented", "Samsung IAP is not implemented yet")

  override fun isAvailable(): Boolean = throw notImplemented()

  override fun setOperationMode(mode: String) = throw notImplemented()

  override fun getProductsDetails(itemIdsCsv: String, callback: (Result<List<ProductMsg>>) -> Unit) =
    callback(Result.failure(notImplemented()))

  override fun getOwnedList(productType: String, callback: (Result<List<PurchaseMsg>>) -> Unit) =
    callback(Result.failure(notImplemented()))

  override fun startPayment(
    itemId: String,
    obfuscatedAccountId: String?,
    obfuscatedProfileId: String?,
    callback: (Result<PurchaseResultMsg>) -> Unit,
  ) = callback(Result.failure(notImplemented()))

  override fun acknowledgePurchases(purchaseIds: List<String>, callback: (Result<List<AckResultMsg>>) -> Unit) =
    callback(Result.failure(notImplemented()))

  override fun consumePurchasedItems(purchaseIds: List<String>, callback: (Result<List<AckResultMsg>>) -> Unit) =
    callback(Result.failure(notImplemented()))

  override fun getPromotionEligibility(itemIdsCsv: String, callback: (Result<String>) -> Unit) =
    callback(Result.failure(notImplemented()))

  override fun changeSubscriptionPlan(
    oldItemId: String,
    newItemId: String,
    prorationMode: String,
    callback: (Result<PurchaseResultMsg>) -> Unit,
  ) = callback(Result.failure(notImplemented()))
}
