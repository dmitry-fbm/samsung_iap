package online.`as`.samsung_iap

import android.app.Activity
import android.app.Application
import android.content.Context
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.samsung.android.sdk.iap.lib.activity.BaseActivity
import com.samsung.android.sdk.iap.lib.service.ServiceScheduler
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * Works around an IAP SDK 6.5.2 hang when its payment screen goes away without a result.
 *
 * The SDK reports a payment and runs the calls it queued behind it (`IapHelper` queues every call
 * made while an operation is running) only from `BaseActivity.finish()`. When the system destroys
 * the screen instead (its task removed from Recents, or the screen torn down while the user is
 * away), `onDestroy` just clears the running flag. The payment listener never fires and the queue
 * never drains. A later call doesn't help either: the app's startup `getOwnedList` itself waits in
 * that queue. Seen 2026-11-11: a payment left mid-way, then the app swiped away and relaunched in
 * the same process (the payment task kept it alive), hung at its owned-list check.
 *
 * On such a destroy this reports the open payment as cancelled ([cancel] callbacks) and drains
 * the queue. It runs after the SDK's own `onDestroy` (posted), so the SDK has cleared its flag.
 * After a normal `finish()` it is harmless: the payment already reported (no cancel), and the
 * drain skips while a queued call runs or finds the queue empty.
 *
 * Plain logic with injected effects; [SdkActivityWatcher] wires it to the Android lifecycle.
 */
class AbandonedPaymentRecovery(
  private val post: (() -> Unit) -> Unit,
  private val drainQueue: () -> Unit,
  private val log: (String) -> Unit = {},
) {
  private val cancel = AtomicReference<(() -> Unit)?>(null)

  /** A payment screen is about to open; [cancelPayment] reports it as cancelled. */
  fun paymentStarted(cancelPayment: () -> Unit) = cancel.set(cancelPayment)

  /** The payment reported a result through the SDK listener. */
  fun paymentFinished() = cancel.set(null)

  fun sdkActivityDestroyed(changingConfigurations: Boolean) {
    if (changingConfigurations) return
    post {
      cancel.getAndSet(null)?.let {
        log("payment screen closed without a result; reporting it as cancelled")
        it()
      }
      drainQueue()
    }
  }
}

/**
 * Process-wide: the SDK's queue and payment screen outlive any one Flutter engine, so a
 * recovery must reach an engine attached after the payment's own engine detached.
 */
object SdkActivityWatcher : Application.ActivityLifecycleCallbacks {
  private const val TAG = "SamsungIap"
  private val installed = AtomicBoolean(false)

  val recovery =
    AbandonedPaymentRecovery(
      post = { Handler(Looper.getMainLooper()).post(it) },
      // `ServiceScheduler` is undocumented SDK API (verified in 6.5.2, the pinned version):
      // re-verify it, and whether this workaround is still needed, on any SDK version bump.
      drainQueue = {
        try {
          ServiceScheduler.runNextService()
        } catch (e: Exception) {
          Log.e(TAG, "drain of the IAP queue failed", e)
        }
      },
      log = { Log.w(TAG, it) },
    )

  fun install(context: Context) {
    if (!installed.compareAndSet(false, true)) return
    (context.applicationContext as Application).registerActivityLifecycleCallbacks(this)
  }

  override fun onActivityDestroyed(activity: Activity) {
    if (activity !is BaseActivity) return
    recovery.sdkActivityDestroyed(activity.isChangingConfigurations)
  }

  override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit

  override fun onActivityStarted(activity: Activity) = Unit

  override fun onActivityResumed(activity: Activity) = Unit

  override fun onActivityPaused(activity: Activity) = Unit

  override fun onActivityStopped(activity: Activity) = Unit

  override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
}
