package com.teacher.schedule_plan

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    /**
     * 应用内自更新用到的原生能力（取自身 APK 路径 / 剩余空间 / 拉起安装器）。
     * 具体实现见 [ApkInstallerChannel]。
     */
    private var apkInstallerChannel: ApkInstallerChannel? = null

    /**
     * 专注模式用到的原生能力（屏幕常亮 / 屏幕固定 / 提示音）。
     * 具体实现见 [FocusLockChannel]。
     *
     * 这里传的是 Activity 本身而不是 applicationContext ——
     * `startLockTask()` / `stopLockTask()` 是 Activity 的方法，
     * 窗口标志也只有挂在 Activity 的 window 上才生效。
     */
    private var focusLockChannel: FocusLockChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        apkInstallerChannel = ApkInstallerChannel(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        focusLockChannel = FocusLockChannel(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
        )
    }

    override fun onDestroy() {
        // ToneGenerator 会占着音频通道，必须显式释放。
        focusLockChannel?.dispose()
        focusLockChannel = null
        super.onDestroy()
    }
}
