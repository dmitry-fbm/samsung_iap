package online.`as`.samsung_iap

import java.util.TimeZone
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SamsungValuesTest {
  private val riga = TimeZone.getTimeZone("Europe/Riga")

  @Test
  fun `local winter time is shifted to UTC`() {
    assertEquals("2026-01-15 08:30:00", SamsungValues.utcDate("2026-01-15 10:30:00", riga))
  }

  @Test
  fun `local summer time uses the DST offset`() {
    assertEquals("2026-07-15 07:30:00", SamsungValues.utcDate("2026-07-15 10:30:00", riga))
  }

  @Test
  fun `shift crosses the date line`() {
    assertEquals(
      "2026-01-01 05:00:00",
      SamsungValues.utcDate("2025-12-31 21:00:00", TimeZone.getTimeZone("America/Los_Angeles")),
    )
  }

  @Test
  fun `UTC device leaves the value unchanged`() {
    assertEquals("2026-03-01 00:00:00", SamsungValues.utcDate("2026-03-01 00:00:00", TimeZone.getTimeZone("UTC")))
  }

  @Test
  fun `malformed values do not parse`() {
    for (bad in listOf("", "2026-01-15", "2026-01-15T10:30:00", "2026-13-01 00:00:00", "2026-01-15 10:30:00x")) {
      assertNull(SamsungValues.utcDate(bad, riga), bad)
    }
  }

  @Test
  fun `obfuscated id validity`() {
    assertTrue(SamsungValues.isValidObfuscatedId("a".repeat(64)))
    assertFalse(SamsungValues.isValidObfuscatedId("a".repeat(65)))
    assertFalse(SamsungValues.isValidObfuscatedId("user@example.com"))
  }
}
