package com.example.pickup_app

import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import android.webkit.WebView
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.webviewflutter.WebViewFlutterAndroidExternalApi

class MainActivity : FlutterActivity() {
    private val WEBVIEW_HOOK_CHANNEL = "com.example.pickup_app/webview_hook"
    private val POWER_CHANNEL = "com.example.pickup_app/power"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // WebView 原生桥接：document-start JS 注入 + 保留安全属性的 Cookie 写入
        val hookChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WEBVIEW_HOOK_CHANNEL)
        hookChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setCookie" -> {
                    val url = call.argument<String>("url")
                    val cookie = call.argument<String>("cookie")
                    if (url != null && cookie != null) {
                        try {
                            val cm = android.webkit.CookieManager.getInstance()
                            cm.setCookie(url, cookie)
                            cm.flush()
                            result.success(true)
                        } catch (e: Throwable) {
                            android.util.Log.w("PddHook", "setCookie failed: $e")
                            result.success(false)
                        }
                    } else {
                        result.error("INVALID_ARGS", "url and cookie required", null)
                    }
                }
                "installDocumentStartHook" -> {
                    val identifier = (call.argument<Number>("identifier"))?.toLong()
                    val script = call.argument<String>("script")
                    // origins 必须由调用方显式声明白名单；缺省为空集合（脚本不生效），避免默认放行所有站点
                    val origins = call.argument<List<String>>("origins") ?: emptyList<String>()

                    if (identifier != null && script != null) {
                        try {
                            val webView = WebViewFlutterAndroidExternalApi.getWebView(flutterEngine, identifier)
                            if (webView != null && WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
                                WebViewCompat.addDocumentStartJavaScript(
                                    webView,
                                    script,
                                    origins.toSet()
                                )
                                android.util.Log.i("PddHook", "Successfully installed document-start script on webview $identifier")
                                result.success(true)
                            } else {
                                android.util.Log.w("PddHook", "WebView null or DOCUMENT_START_SCRIPT unsupported on webview $identifier")
                                result.success(false)
                            }
                        } catch (e: Throwable) {
                            android.util.Log.e("PddHook", "Error installing document-start script: $e")
                            result.success(false)
                        }
                    } else {
                        result.error("INVALID_ARGS", "identifier and script required", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // 电池优化豁免：状态查询 + 系统授权弹窗（保活设置页使用）
        val powerChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, POWER_CHANNEL)
        powerChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isIgnoringBatteryOptimizations" -> result.success(isIgnoringBatteryOptimizations())
                "requestIgnoreBatteryOptimizations" -> {
                    if (!isIgnoringBatteryOptimizations()) {
                        try {
                            startActivity(
                                Intent(
                                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                    Uri.parse("package:$packageName")
                                )
                            )
                        } catch (e: Throwable) {
                            // 部分 ROM 不支持带包名的直接申请，退回电池优化列表
                            try {
                                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                            } catch (_: Throwable) {}
                        }
                    }
                    result.success(isIgnoringBatteryOptimizations())
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }
}
