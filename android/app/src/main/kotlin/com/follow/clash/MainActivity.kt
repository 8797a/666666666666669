package com.follow.clash

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
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
import kotlin.system.exitProcess

class MainActivity : FlutterActivity(),
    CoroutineScope by CoroutineScope(SupervisorJob() + Dispatchers.Default) {

    private val HARDWARE_CHANNEL = "com.follow/hardware"
    private val PERMISSION_REQUEST_CODE = 1001

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // 检查并请求权限
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            checkAndRequestPermission()
        }
    }

    private fun checkAndRequestPermission() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) 
            != PackageManager.PERMISSION_GRANTED) {
            // 请求权限
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.READ_PHONE_STATE),
                PERMISSION_REQUEST_CODE
            )
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        
        if (requestCode == PERMISSION_REQUEST_CODE) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                // 权限已授予
            } else {
                // 权限被拒绝，退出应用
                finishAffinity()
                exitProcess(0)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(AppPlugin())
        flutterEngine.plugins.add(ServicePlugin())
        flutterEngine.plugins.add(TilePlugin())
        State.flutterEngine = flutterEngine
        
        // 设置硬件信息获取通道
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
            // Android 无法直接获取 CPU ID，使用 CPU 架构和型号作为标识
            "${Build.SUPPORTED_ABIS.joinToString(",")}_${Build.HARDWARE}"
        } catch (e: Exception) {
            ""
        }
    }

    private fun getBoardSerial(): String {
        return try {
            // 检查权限
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) 
                    == PackageManager.PERMISSION_GRANTED) {
                    Build.getSerial()
                } else {
                    ""
                }
            } else {
                @Suppress("DEPRECATION")
                Build.SERIAL
            }
        } catch (e: Exception) {
            ""
        }
    }

    private fun getDiskSerial(): String {
        return try {
            // Android 使用设备型号和制造商作为标识
            "${Build.MANUFACTURER}_${Build.MODEL}_${Build.DEVICE}"
        } catch (e: Exception) {
            ""
        }
    }

    private fun getAndroidId(): String {
        return try {
            // 获取 Android ID（设备唯一标识）
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