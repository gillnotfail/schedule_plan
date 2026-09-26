package com.teacher.schedule_plan

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    /**
     * 应用内自更新用到的原生能力（取自身 APK 路径 / 剩余空间 / 拉起安装器）。
     * 具体实现见 [ApkInstallerChannel]。
     */
    private var apkInstallerChannel: ApkInstallerChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        apkInstallerChannel = ApkInstallerChannel(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
    }
}
