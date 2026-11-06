package online.`as`.samsung_iap

import android.app.Activity
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding

/** Registers [SamsungIapHostApi] and tracks the current [Activity] (needed by startPayment). */
class SamsungIapPlugin : FlutterPlugin, ActivityAware {
  private var activity: Activity? = null
  private var binding: FlutterPlugin.FlutterPluginBinding? = null

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    binding = flutterPluginBinding
    SamsungIapHostApi.setUp(flutterPluginBinding.binaryMessenger, IapHostApiImpl { activity })
  }

  override fun onDetachedFromEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    SamsungIapHostApi.setUp(flutterPluginBinding.binaryMessenger, null)
    binding = null
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivityForConfigChanges() {
    activity = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivity() {
    activity = null
  }
}
