package com.roleplay.ai_roleplay

import android.os.Build
import android.util.Log
import android.view.WindowInsetsController
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    /// 最近一次由 Dart 下发的图标明暗（true = 浅色图标 / 暗色背景）
    private var lastLight: Boolean? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSystemBarIcons" -> {
                        val light = call.argument<Boolean>("light") ?: false
                        lastLight = light
                        applySystemBarIcons(light)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onPostResume() {
        super.onPostResume()
        // Flutter 引擎在 resume 后可能重新应用它自己的（旧 API）样式，
        // 这里把最近一次的值再压一次。
        lastLight?.let { applySystemBarIcons(it) }
    }

    /// Flutter 3.24 走的是旧的 View.setSystemUiVisibility，而 Android 15+ 强制
    /// edge-to-edge 后会忽略其中的 LIGHT_STATUS_BAR 标志（导航栏标志碰巧还认），
    /// 导致亮色模式下状态栏图标仍是白色、看不清。
    ///
    /// 这里直接操作 window 的 WindowInsetsController（API 30+），并对旧系统用
    /// WindowCompat 兜底；同时在 400ms 后再压一次，避免被 Flutter 引擎首帧后的
    /// 默认样式覆盖。
    private fun applySystemBarIcons(light: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val mask = WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS or
                WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS
            val appearance = if (light) 0 else mask
            window.insetsController?.setSystemBarsAppearance(appearance, mask)
            // Flutter 引擎可能在首帧后再写一次样式，延迟重压保证最终态正确
            window.decorView.postDelayed({
                window.insetsController?.setSystemBarsAppearance(appearance, mask)
            }, 400)
            Log.d(
                "SystemUI",
                "apply light=$light appearance=$appearance now=${window.insetsController?.systemBarsAppearance}",
            )
        }
        // 旧系统兜底
        val compat = WindowCompat.getInsetsController(window, window.decorView)
        compat.isAppearanceLightStatusBars = !light
        compat.isAppearanceLightNavigationBars = !light
    }

    private companion object {
        const val CHANNEL = "app/system_ui"
    }
}
