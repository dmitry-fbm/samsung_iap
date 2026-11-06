package online.`as`.samsung_iap

import java.text.ParseException
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

/** Pure value conversions between the Samsung SDK and the Pigeon messages (no Android calls). */
internal object SamsungValues {
  /** The SDK's date format (`BaseVo.getDateString`), in the device's local time zone. */
  private const val DATE_PATTERN = "yyyy-MM-dd HH:mm:ss"

  /** Longest obfuscated id the SDK accepts (`HelperConstants.MAX_OBFUSCATED_ID_LENGTH`). */
  private const val MAX_OBFUSCATED_ID_LENGTH = 64

  /**
   * Re-expresses an SDK date string, written in [local] time, in UTC with the same pattern.
   * Returns null if [value] does not match the pattern exactly.
   */
  fun utcDate(value: String, local: TimeZone = TimeZone.getDefault()): String? {
    val parser =
      SimpleDateFormat(DATE_PATTERN, Locale.US).apply {
        timeZone = local
        isLenient = false
      }
    val date =
      try {
        parser.parse(value)
      } catch (_: ParseException) {
        null
      } ?: return null
    // Reject trailing text that parse() silently ignores.
    if (parser.format(date) != value) return null
    return SimpleDateFormat(DATE_PATTERN, Locale.US)
      .apply { timeZone = TimeZone.getTimeZone("UTC") }
      .format(date)
  }

  /** False for an id the SDK would refuse (looks like an e-mail, or over 64 chars). */
  fun isValidObfuscatedId(id: String): Boolean = '@' !in id && id.length <= MAX_OBFUSCATED_ID_LENGTH
}
