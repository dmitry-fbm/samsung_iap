package online.`as`.samsung_iap

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class AbandonedPaymentRecoveryTest {
  private val events = mutableListOf<String>()
  private val posted = mutableListOf<() -> Unit>()
  private val recovery =
    AbandonedPaymentRecovery(post = { posted += it }, drainQueue = { events += "drain" })

  private fun runPosted() = posted.toList().also { posted.clear() }.forEach { it() }

  @Test
  fun `a destroyed payment screen cancels the open payment and drains the queue`() {
    recovery.paymentStarted { events += "cancel" }

    recovery.sdkActivityDestroyed(changingConfigurations = false)
    runPosted()

    assertEquals(listOf("cancel", "drain"), events)
  }

  @Test
  fun `the queue is drained even when this engine has no open payment`() {
    // The payment was opened by an engine that has since detached; the new one queued a call.
    recovery.sdkActivityDestroyed(changingConfigurations = false)
    runPosted()

    assertEquals(listOf("drain"), events)
  }

  @Test
  fun `a payment that already reported its result is not cancelled again`() {
    recovery.paymentStarted { events += "cancel" }
    recovery.paymentFinished()

    recovery.sdkActivityDestroyed(changingConfigurations = false)
    runPosted()

    assertEquals(listOf("drain"), events)
  }

  @Test
  fun `a configuration change is not an abandoned payment`() {
    recovery.paymentStarted { events += "cancel" }

    recovery.sdkActivityDestroyed(changingConfigurations = true)
    runPosted()

    assertTrue(events.isEmpty())
  }

  @Test
  fun `the open payment is cancelled only once`() {
    recovery.paymentStarted { events += "cancel" }

    recovery.sdkActivityDestroyed(changingConfigurations = false)
    recovery.sdkActivityDestroyed(changingConfigurations = false)
    runPosted()

    assertEquals(listOf("cancel", "drain", "drain"), events)
  }

  @Test
  fun `recovery waits for the SDK's own onDestroy to finish`() {
    recovery.paymentStarted { events += "cancel" }

    recovery.sdkActivityDestroyed(changingConfigurations = false)

    assertTrue(events.isEmpty())
  }
}
