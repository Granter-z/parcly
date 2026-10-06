package com.example.pickup_app

import android.webkit.WebView
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.webviewflutter.WebViewFlutterAndroidExternalApi

class MainActivity : FlutterActivity() {
    private val WEBVIEW_HOOK_CHANNEL = "com.example.pickup_app/webview_hook"
    private val SECURE_STORE_CHANNEL = "com.example.pickup_app/secure_store"
    private val KEY_ALIAS = "pickup_app_storage_key"

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

        // 平台凭据本地加密桥接：使用 Android Keystore 中的 AES-GCM 主密钥
        val secureChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURE_STORE_CHANNEL)
        secureChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "encrypt" -> {
                    val value = call.argument<String>("value")
                    if (value == null) {
                        result.error("INVALID_ARGS", "value required", null)
                    } else {
                        result.success(encryptValue(value))
                    }
                }
                "decrypt" -> {
                    val value = call.argument<String>("value")
                    if (value == null) {
                        result.error("INVALID_ARGS", "value required", null)
                    } else {
                        result.success(decryptValue(value))
                    }
                }
                "isAvailable" -> result.success(getOrCreateSecretKey() != null)
                else -> result.notImplemented()
            }
        }
    }

    /** 获取（或首次创建）Android Keystore 中的 AES 主密钥；设备不支持时返回 null */
    private fun getOrCreateSecretKey(): javax.crypto.SecretKey? {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.M) return null
        return try {
            val keyStore = java.security.KeyStore.getInstance("AndroidKeyStore")
            keyStore.load(null)
            val entry = keyStore.getEntry(KEY_ALIAS, null) as? java.security.KeyStore.SecretKeyEntry
            if (entry != null) return entry.secretKey

            val generator = javax.crypto.KeyGenerator.getInstance(
                android.security.keystore.KeyProperties.KEY_ALGORITHM_AES,
                "AndroidKeyStore"
            )
            generator.init(
                android.security.keystore.KeyGenParameterSpec.Builder(
                    KEY_ALIAS,
                    android.security.keystore.KeyProperties.PURPOSE_ENCRYPT or
                        android.security.keystore.KeyProperties.PURPOSE_DECRYPT
                )
                    .setBlockModes(android.security.keystore.KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(android.security.keystore.KeyProperties.ENCRYPTION_PADDING_NONE)
                    .build()
            )
            generator.generateKey()
        } catch (e: Throwable) {
            android.util.Log.w("SecureStore", "keystore key unavailable: $e")
            null
        }
    }

    /** AES-GCM 加密，输出 [ivLength(1B) | iv | ciphertext] 的 Base64；不可用时返回 null */
    private fun encryptValue(plain: String): String? {
        val key = getOrCreateSecretKey() ?: return null
        return try {
            val cipher = javax.crypto.Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(javax.crypto.Cipher.ENCRYPT_MODE, key)
            val iv = cipher.iv
            val cipherText = cipher.doFinal(plain.toByteArray(Charsets.UTF_8))
            val buffer = java.nio.ByteBuffer.allocate(1 + iv.size + cipherText.size)
            buffer.put(iv.size.toByte())
            buffer.put(iv)
            buffer.put(cipherText)
            android.util.Base64.encodeToString(buffer.array(), android.util.Base64.NO_WRAP)
        } catch (e: Throwable) {
            android.util.Log.w("SecureStore", "encrypt failed: $e")
            null
        }
    }

    private fun decryptValue(encoded: String): String? {
        val key = getOrCreateSecretKey() ?: return null
        return try {
            val data = android.util.Base64.decode(encoded, android.util.Base64.NO_WRAP)
            val ivLength = data[0].toInt()
            if (ivLength <= 0 || data.size <= ivLength + 1) return null
            val iv = data.copyOfRange(1, 1 + ivLength)
            val cipherText = data.copyOfRange(1 + ivLength, data.size)
            val cipher = javax.crypto.Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(
                javax.crypto.Cipher.DECRYPT_MODE,
                key,
                javax.crypto.spec.GCMParameterSpec(128, iv)
            )
            String(cipher.doFinal(cipherText), Charsets.UTF_8)
        } catch (e: Throwable) {
            android.util.Log.w("SecureStore", "decrypt failed: $e")
            null
        }
    }
}
