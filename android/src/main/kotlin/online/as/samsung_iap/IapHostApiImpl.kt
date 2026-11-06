package online.`as`.samsung_iap

import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.samsung.android.sdk.iap.lib.constants.HelperDefine
import com.samsung.android.sdk.iap.lib.constants.HelperDefine.AcknowledgedStatus
import com.samsung.android.sdk.iap.lib.constants.HelperDefine.OperationMode
import com.samsung.android.sdk.iap.lib.constants.HelperDefine.ProrationMode
import com.samsung.android.sdk.iap.lib.helper.IapHelper
import com.samsung.android.sdk.iap.lib.util.HelperUtil
import com.samsung.android.sdk.iap.lib.vo.ConsumeVo
import com.samsung.android.sdk.iap.lib.vo.ErrorVo
import com.samsung.android.sdk.iap.lib.vo.OwnedProductVo
import com.samsung.android.sdk.iap.lib.vo.ProductVo
import com.samsung.android.sdk.iap.lib.vo.PromotionEligibilityVo
import com.samsung.android.sdk.iap.lib.vo.PurchaseVo
import java.util.concurrent.atomic.AtomicBoolean
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

/**
 * [SamsungIapHostApi] over Samsung's `IapHelper` (IAP SDK 6.5.2).
 *
 * Pigeon invokes every method on the platform (main) thread, which is where `IapHelper` expects
 * to be called. Every async method completes its callback exactly once ([Once]).
 *
 * Error contract (controller ruling):
 *  - Non-payment calls (getProductsDetails, getOwnedList, acknowledgePurchases,
 *    consumePurchasedItems, getPromotionEligibility) report failure by completing the callback with
 *    `Result.failure(FlutterError(code = <Samsung errorCode as string>, message = <errorString>))`.
 *  - Payment calls (startPayment, changeSubscriptionPlan) NEVER fail the callback: errors are
 *    returned as `ErrorMsg` inside `PurchaseResultMsg` so Dart can map cancel
 *    (`IAP_PAYMENT_IS_CANCELED` = 1) to `canceled`.
 *    (No activity: `ErrorMsg(code = -1, message = "no activity")`.)
 *
 * The SDK swallows some failures (it logs and returns `false`, or returns nothing at all from
 * `getProductsDetails`) without ever calling the listener. Those paths are covered here: a Galaxy
 * Store pre-check before every non-payment store call, and a `false` return becomes an
 * `IAP_ERROR_COMMON` failure.
 */
class IapHostApiImpl(
  context: Context,
  private val activityProvider: () -> Activity?,
) : SamsungIapHostApi {

  private val appContext: Context = context.applicationContext

  /** Process-wide singleton; it holds the operation mode set by [setOperationMode]. */
  private val helper: IapHelper by lazy { IapHelper.getInstance(appContext) }

  override fun isAvailable(): Boolean =
    try {
      appContext.packageManager.getApplicationInfo(GALAXY_STORE_PACKAGE, 0).enabled
    } catch (_: PackageManager.NameNotFoundException) {
      false
    }

  override fun setOperationMode(mode: String) {
    val operationMode =
      when (mode) {
        "production" -> OperationMode.OPERATION_MODE_PRODUCTION
        "test" -> OperationMode.OPERATION_MODE_TEST
        "test_failure" -> OperationMode.OPERATION_MODE_TEST_FAILURE
        else -> throw FlutterError("invalid_argument", "Unknown operation mode: $mode")
      }
    helper.setOperationMode(operationMode)
  }

  override fun getProductsDetails(itemIdsCsv: String, callback: (Result<List<ProductMsg>>) -> Unit) {
    val once = Once("getProductsDetails", callback)
    if (!storeReady(once)) return
    // Returns nothing: its only silent failure (invalid Galaxy Store) is pre-checked above.
    helper.getProductsDetails(itemIdsCsv) { error, products ->
      once.complete(error) { products.orEmpty().map(::productMsg) }
    }
  }

  override fun getOwnedList(productType: String, callback: (Result<List<PurchaseMsg>>) -> Unit) {
    val once = Once("getOwnedList", callback)
    if (!storeReady(once)) return
    val started =
      helper.getOwnedList(productType) { error, owned ->
        once.complete(error) { owned.orEmpty().map(::ownedPurchaseMsg) }
      }
    if (!started) once.fail(notStarted("getOwnedList"))
  }

  override fun startPayment(
    itemId: String,
    obfuscatedAccountId: String?,
    obfuscatedProfileId: String?,
    callback: (Result<PurchaseResultMsg>) -> Unit,
  ) {
    val once = Once("startPayment", callback)
    if (activityProvider() == null) return once.succeed(NO_ACTIVITY)
    val started =
      helper.startPayment(itemId, obfuscatedAccountId, obfuscatedProfileId) { error, purchase ->
        once.succeed(purchaseResult(error, purchase))
      }
    // False when another IAP operation is running or an argument is invalid (e.g. an
    // obfuscated id over 64 chars or in e-mail form); the listener is then never called.
    if (!started) once.succeed(notStartedResult("startPayment"))
  }

  override fun acknowledgePurchases(purchaseIds: List<String>, callback: (Result<List<AckResultMsg>>) -> Unit) {
    val once = Once("acknowledgePurchases", callback)
    if (purchaseIds.isEmpty()) return once.succeed(emptyList())
    if (!storeReady(once)) return
    val started =
      helper.acknowledgePurchases(purchaseIds.joinToString(",")) { error, results ->
        once.complete(error) { results.orEmpty().map(::ackResultMsg) }
      }
    // Also false when Galaxy Store is older than 4.5.90 (no acknowledge support).
    if (!started) once.fail(notStarted("acknowledgePurchases"))
  }

  override fun consumePurchasedItems(purchaseIds: List<String>, callback: (Result<List<AckResultMsg>>) -> Unit) {
    val once = Once("consumePurchasedItems", callback)
    if (purchaseIds.isEmpty()) return once.succeed(emptyList())
    if (!storeReady(once)) return
    val started =
      helper.consumePurchasedItems(purchaseIds.joinToString(",")) { error, results ->
        once.complete(error) { results.orEmpty().map(::ackResultMsg) }
      }
    if (!started) once.fail(notStarted("consumePurchasedItems"))
  }

  override fun getPromotionEligibility(itemIdsCsv: String, callback: (Result<String>) -> Unit) {
    val once = Once("getPromotionEligibility", callback)
    if (!storeReady(once)) return
    val started =
      helper.getPromotionEligibility(itemIdsCsv) { error, pricing ->
        once.complete(error) { promotionJson(pricing.orEmpty()) }
      }
    if (!started) once.fail(notStarted("getPromotionEligibility"))
  }

  override fun changeSubscriptionPlan(
    oldItemId: String,
    newItemId: String,
    prorationMode: String,
    callback: (Result<PurchaseResultMsg>) -> Unit,
  ) {
    val once = Once("changeSubscriptionPlan", callback)
    if (activityProvider() == null) return once.succeed(NO_ACTIVITY)
    val mode =
      ProrationMode.entries.firstOrNull { it.name == prorationMode }
        ?: return once.succeed(
          errorResult(HelperDefine.IAP_ERROR_COMMON, "Unknown prorationMode: $prorationMode")
        )
    val started =
      helper.changeSubscriptionPlan(oldItemId, newItemId, mode) { error, purchase ->
        once.succeed(purchaseResult(error, purchase))
      }
    if (!started) once.succeed(notStartedResult("changeSubscriptionPlan"))
  }

  /**
   * The SDK's own Galaxy Store check (installed, enabled, genuine, recent enough). When it fails
   * the SDK shows its guidance dialog and would skip the listener, so the call is failed here.
   */
  private fun storeReady(once: Once<*>): Boolean {
    if (HelperUtil.isGalaxyStoreValid(appContext)) return true
    once.fail(
      FlutterError("${HelperDefine.IAP_ERROR_INITIALIZATION}", "Galaxy Store is not valid on the device.")
    )
    return false
  }

  /**
   * Completes [callback] exactly once, on the main thread. Later completions (an SDK listener
   * firing twice) are logged and dropped.
   */
  private class Once<T>(private val operation: String, private val callback: (Result<T>) -> Unit) {
    private val done = AtomicBoolean(false)

    fun succeed(value: T) = finish(Result.success(value))

    fun fail(error: FlutterError) = finish(Result.failure(error))

    /** Success from [value] when [error] is `IAP_ERROR_NONE`, otherwise a [FlutterError]. */
    fun complete(error: ErrorVo?, value: () -> T) =
      if (error != null && error.errorCode == HelperDefine.IAP_ERROR_NONE) {
        succeed(value())
      } else {
        fail(flutterError(error))
      }

    private fun finish(result: Result<T>) {
      if (!done.compareAndSet(false, true)) {
        Log.w(TAG, "$operation: ignoring a repeated completion")
        return
      }
      if (Looper.myLooper() == Looper.getMainLooper()) {
        callback(result)
      } else {
        Handler(Looper.getMainLooper()).post { callback(result) }
      }
    }
  }

  private companion object {
    const val TAG = "SamsungIap"
    const val GALAXY_STORE_PACKAGE = "com.sec.android.app.samsungapps"
    const val NO_ERROR_OBJECT = "IapHelper returned no error object"

    val NO_ACTIVITY = errorResult(-1, "no activity")

    fun notStartedMessage(operation: String) = "$operation was not started by IapHelper (see logcat)"

    fun notStarted(operation: String) =
      FlutterError("${HelperDefine.IAP_ERROR_COMMON}", notStartedMessage(operation))

    fun notStartedResult(operation: String) =
      errorResult(HelperDefine.IAP_ERROR_COMMON, notStartedMessage(operation))

    fun errorResult(code: Int, message: String) =
      PurchaseResultMsg(error = ErrorMsg(code.toLong(), message))

    fun flutterError(error: ErrorVo?) =
      if (error == null) {
        FlutterError("${HelperDefine.IAP_ERROR_COMMON}", NO_ERROR_OBJECT)
      } else {
        FlutterError("${error.errorCode}", error.errorString.orEmpty())
      }

    fun purchaseResult(error: ErrorVo?, purchase: PurchaseVo?): PurchaseResultMsg =
      when {
        error == null -> errorResult(HelperDefine.IAP_ERROR_COMMON, NO_ERROR_OBJECT)
        error.errorCode != HelperDefine.IAP_ERROR_NONE ->
          errorResult(error.errorCode, error.errorString.orEmpty())
        else -> PurchaseResultMsg(purchase = purchase?.let(::purchaseMsg))
      }

    fun productMsg(p: ProductVo) =
      ProductMsg(
        itemId = p.itemId.orEmpty(),
        itemName = p.itemName.orEmpty(),
        itemPriceString = p.itemPriceString.orEmpty(),
        itemPrice = p.itemPrice ?: 0.0,
        currencyCode = p.currencyCode.orEmpty(),
        itemDesc = p.itemDesc.orEmpty(),
        type = p.type.orEmpty(),
        subscriptionDurationUnit = p.subscriptionDurationUnit.nullIfEmpty(),
        subscriptionDurationMultiplier = p.subscriptionDurationMultiplier?.trim()?.toLongOrNull(),
        freeTrialPeriod = p.freeTrialPeriod.nullIfEmpty(),
      )

    /** A fresh payment is not acknowledged yet and carries no subscription end date. */
    fun purchaseMsg(p: PurchaseVo) =
      PurchaseMsg(
        itemId = p.itemId.orEmpty(),
        purchaseId = p.purchaseId.orEmpty(),
        paymentId = p.paymentId.orEmpty(),
        orderId = p.orderId.orEmpty(),
        purchaseDate = p.purchaseDate.orEmpty(),
        type = p.type.orEmpty(),
        acknowledged = false,
        obfuscatedAccountId = p.obfuscatedAccountId.nullIfEmpty(),
        obfuscatedProfileId = p.obfuscatedProfileId.nullIfEmpty(),
        jsonString = p.jsonString.orEmpty(),
      )

    /**
     * `OwnedProductVo` has no order id. Only `NOT_ACKNOWLEDGED` needs acknowledging;
     * `UNSUPPORTED` (e.g. consumables) is treated as nothing to acknowledge.
     */
    fun ownedPurchaseMsg(p: OwnedProductVo) =
      PurchaseMsg(
        itemId = p.itemId.orEmpty(),
        purchaseId = p.purchaseId.orEmpty(),
        paymentId = p.paymentId.orEmpty(),
        orderId = "",
        purchaseDate = p.purchaseDate.orEmpty(),
        type = p.type.orEmpty(),
        acknowledged = p.acknowledgedStatus != AcknowledgedStatus.NOT_ACKNOWLEDGED,
        subscriptionEndDate = p.subscriptionEndDate.nullIfEmpty(),
        obfuscatedAccountId = p.obfuscatedAccountId.nullIfEmpty(),
        obfuscatedProfileId = p.obfuscatedProfileId.nullIfEmpty(),
        jsonString = p.jsonString.orEmpty(),
      )

    /** `AcknowledgeVo` extends `ConsumeVo`. */
    fun ackResultMsg(r: ConsumeVo) =
      AckResultMsg(
        purchaseId = r.purchaseId.orEmpty(),
        statusCode = r.statusCode.toLong(),
        statusString = r.statusString.nullIfEmpty(),
      )

    /** The SDK's per-item JSON objects, as one JSON array. */
    fun promotionJson(pricing: List<PromotionEligibilityVo>): String =
      JSONArray()
        .apply {
          pricing.forEach { vo ->
            try {
              put(JSONObject(vo.jsonString.orEmpty()))
            } catch (e: JSONException) {
              Log.w(TAG, "getPromotionEligibility: unparsable item ${vo.itemId}", e)
            }
          }
        }
        .toString()

    fun String?.nullIfEmpty(): String? = if (isNullOrEmpty()) null else this
  }
}
