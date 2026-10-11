package site.massawallet.app

import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MainActivity — FlutterFragmentActivity (required by local_auth) with a
 * FLAG_SECURE toggle channel for the screenshot guard.
 */
class MainActivity : FlutterFragmentActivity() {
    private val channelName = "site.massawallet.app/security"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecureFlag" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        runOnUiThread {
                            if (enabled) {
                                window.setFlags(
                                    WindowManager.LayoutParams.FLAG_SECURE,
                                    WindowManager.LayoutParams.FLAG_SECURE
                                )
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            }
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        // Homescreen widget refresh channel (widget_service.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "site.massawallet.app/widget")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "refresh" -> {
                        MassaWidgetProvider.updateAll(applicationContext)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        // Embedded node channel: exposes the native library directory,
        // where the bundled massa-node executable (libmassa_node.so)
        // is extracted and may be exec()'d (W^X-compliant location).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "site.massawallet.app/embedded")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getNativeLibDir" -> result.success(applicationInfo.nativeLibraryDir)
                    else -> result.notImplemented()
                }
            }
        // Background-reliability channel: SDK level (gates the legacy FGS
        // — Android 15 caps dataSync FGS at 6 h/day) and battery-
        // optimization exemption (lifts Doze/App-Standby deferrals for
        // WorkManager via the official system dialog).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "site.massawallet.app/system")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "androidSdkInt" -> result.success(android.os.Build.VERSION.SDK_INT)
                    "isIgnoringBatteryOptimizations" -> {
                        val pm = getSystemService(
                            android.content.Context.POWER_SERVICE
                        ) as android.os.PowerManager
                        result.success(pm.isIgnoringBatteryOptimizations(packageName))
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        try {
                            val intent = android.content.Intent(
                                android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                android.net.Uri.parse("package:$packageName")
                            )
                            intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (_: Exception) {
                            // Some OEM builds reject the action — the user
                            // can still set "Unrestricted" manually.
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
