// SPDX-FileCopyrightText: 2026 Pace Wisdom Solutions Pvt. Ltd.
// SPDX-FileCopyrightText: 2026 Ahmed Elwakeel
// SPDX-License-Identifier: Apache-2.0
package com.tutorloom.student

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Bundle
import android.os.Build
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "sibawayh/security").setMethodCallHandler { call, result ->
            try {
                if (call.method == "deviceIdentity") {
                    val androidId = Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
                    if (androidId.isNullOrBlank()) {
                        result.error("DEVICE_ID", "تعذر التعرف على هذا الجهاز", null)
                        return@setMethodCallHandler
                    }
                    val value = "$androidId:${applicationContext.packageName}"
                    val id = MessageDigest.getInstance("SHA-256")
                        .digest(value.toByteArray())
                        .joinToString("") { "%02x".format(it) }
                    val label = "${Build.MANUFACTURER} ${Build.MODEL}".trim()
                    result.success(mapOf("id" to id, "label" to label))
                    return@setMethodCallHandler
                }
                if (call.method != "status") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val connectivity = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                val vpn = connectivity.allNetworks.any { network -> connectivity.getNetworkCapabilities(network)?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true }
                val proxy = connectivity.defaultProxy != null
                val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                val headphones = audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any { d ->
                    d.type in setOf(AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_WIRED_HEADSET,
                        AudioDeviceInfo.TYPE_USB_HEADSET, AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
                        AudioDeviceInfo.TYPE_BLUETOOTH_SCO, AudioDeviceInfo.TYPE_HEARING_AID, 26)
                }
                result.success(mapOf("vpn" to vpn, "proxy" to proxy, "headphones" to headphones))
            } catch (e: Exception) { result.error("SECURITY_CHECK", "تعذر فحص الاتصال", null) }
        }
    }
}
