package com.follow.clash

import android.os.Build
import android.os.Bundle
import android.provider.Settings
import com.follow.clash.common.GlobalState
import com.follow.clash.plugins.AppPlugin
import com.follow.clash.plugins.ServicePlugin
import com.follow.clash.plugins.TilePlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class MainActivity : FlutterActivity(),
    CoroutineScope by CoroutineScope(SupervisorJob() + Dispatchers.Default) {

    private val HARDWARE_CHANNEL = "com.follow/hardware"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(AppPlugin())
        flutterEngine.plugins.add(ServicePlugin())
        flutterEngine.plugins.add(TilePlugin())
        State.flutterEngine = flutterEngine
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HARDWARE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCpuId" -> {
                    result.success(getCpuId())
                }
                "getBoardSerial" -> {
                    result.success(getBoardSerial())
                }
                "getDiskSerial" -> {
                    result.success(getDiskSerial())
                }
                "getAndroidId" -> {
                    result.success(getAndroidId())
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun getCpuId(): String {
        return try {
            "${Build.SUPPORTED_ABIS.joinToString(",")}_${Build.HARDWARE}"
        } catch (e: Exception) {
            ""
        }
    }

    private fun getBoardSerial(): String {
        return try {
            "${Build.BOARD}_${Build.BRAND}_${Build.PRODUCT}"
        } catch (e: Exception) {
            ""
        }
    }

    private fun getDiskSerial(): String {
        return try {
            "${Build.MANUFACTURER}_${Build.MODEL}_${Build.DEVICE}"
        } catch (e: Exception) {
            ""
        }
    }

    private fun getAndroidId(): String {
        return try {
            Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID) ?: ""
        } catch (e: Exception) {
            ""
        }
    }

    override fun onDestroy() {
        GlobalState.launch {
            Service.setEventListener(null)
        }
        State.flutterEngine = null
        super.onDestroy()
    }
}