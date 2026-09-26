package com.teacher.schedule_plan

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.os.StatFs
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 应用内自更新所需的原生能力。
 *
 * 为什么用 PackageInstaller 而不是 Intent.ACTION_VIEW + FileProvider
 * ---------------------------------------------------------------
 * 后者必须把 APK 暴露成 `content://` URI 交给系统安装器，于是要额外声明
 * 一个 FileProvider 并依赖 `androidx.core`。本项目的 FileProvider 是
 * share_plus 带进来的，直接 import 等于把编译期正确性押在别人的依赖可见性上
 * （如果对方哪天把 `api` 改成 `implementation`，这里就编不过）。
 * `PackageInstaller` 是"把字节写进安装会话管道"，**根本不需要 URI**，
 * 顺带还能通过 [InstallResultReceiver] 拿到真实的安装结果。
 *
 * 另一个必须记住的前提：Android 8.0 起，发起安装的应用自己得先被授予
 * 「安装未知应用」。没授予时 createSession 会直接抛 SecurityException，
 * 所以这里先查再装，避免用户点了按钮却只看到一句"安装失败"。
 */
class ApkInstallerChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL_NAME).apply {
        setMethodCallHandler(this@ApkInstallerChannel)
    }

    init {
        activeChannel = channel
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // 正在运行的这份 APK 自己。分差升级要拿它当基础包——
            // 必须就是设备上跑着的字节，而不是发布包里那一份。
            "installedApkPath" -> result.success(context.applicationInfo.sourceDir)

            // 目录由原生给出，不让 Dart 侧用 path_provider 猜：
            // Android 上 getApplicationSupportDirectory /
            // getApplicationDocumentsDirectory 具体映射到哪个目录有版本差异，
            // 写偏了原生侧就读不到这个文件。
            "prepareWorkDir" -> result.success(workDir().absolutePath)

            "canInstallPackages" -> result.success(canInstallPackages())

            "openInstallPermissionSettings" -> {
                openInstallPermissionSettings()
                result.success(null)
            }

            "freeDiskBytes" -> result.success(freeDiskBytes())

            "install" -> {
                val path = call.argument<String>("path")
                if (path.isNullOrBlank()) {
                    result.error("bad_args", "缺少 path 参数", null)
                } else {
                    result.success(startInstall(path))
                }
            }

            else -> result.notImplemented()
        }
    }

    /** 下载与合成的落地目录。放在 filesDir 下，卸载时随应用一起清掉。 */
    private fun workDir(): File {
        val dir = File(context.filesDir, "updates")
        if (!dir.exists()) {
            dir.mkdirs()
        }
        return dir
    }

    private fun canInstallPackages(): Boolean =
        context.packageManager.canRequestPackageInstalls()

    private fun freeDiskBytes(): Long = try {
        StatFs(context.filesDir.absolutePath).availableBytes
    } catch (error: Throwable) {
        0L
    }

    /**
     * 只接受本应用私有目录里的文件。
     *
     * 这条限制不是形式主义：安装接口会把字节交给系统安装器，
     * 放任意路径进来等于给"让别人指定路径"留了口子。
     */
    private fun isInsideAppStorage(file: File): Boolean = try {
        val target = file.canonicalPath
        val roots = listOf(
            context.filesDir.canonicalPath,
            context.cacheDir.canonicalPath,
        )
        roots.any { target.startsWith("$it${File.separator}") }
    } catch (error: Throwable) {
        false
    }

    private fun startInstall(path: String): Boolean {
        val file = File(path)
        if (!file.isFile || !file.exists()) {
            return false
        }
        if (!isInsideAppStorage(file)) {
            return false
        }
        if (!canInstallPackages()) {
            return false
        }
        return try {
            val installer = context.packageManager.packageInstaller
            val params = PackageInstaller.SessionParams(
                PackageInstaller.SessionParams.MODE_FULL_INSTALL
            )
            params.setAppPackageName(context.packageName)

            val sessionId = installer.createSession(params)
            installer.openSession(sessionId).use { session ->
                session.openWrite("base.apk", 0, file.length()).use { output ->
                    file.inputStream().use { input -> input.copyTo(output) }
                    session.fsync(output)
                }
                session.commit(pendingIntentFor(sessionId).intentSender)
            }
            true
        } catch (error: Throwable) {
            false
        }
    }

    private fun pendingIntentFor(sessionId: Int): PendingIntent {
        val intent = Intent(context, InstallResultReceiver::class.java).apply {
            putExtra(PackageInstaller.EXTRA_SESSION_ID, sessionId)
        }
        // Android 12 起，交给 PackageInstaller 的 PendingIntent 必须是可变的；
        // 低版本没有这个常量，也不能乱传未知标志位，所以按版本分支。
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        return PendingIntent.getBroadcast(context, sessionId, intent, flags)
    }

    private fun openInstallPermissionSettings() {
        val packageUri = Uri.parse("package:${context.packageName}")
        val intents = listOf(
            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, packageUri),
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, packageUri),
        )
        for (intent in intents) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                context.startActivity(intent)
                return
            } catch (error: Throwable) {
                // 某些定制 ROM 没有这个页面，退到应用详情页继续试。
            }
        }
    }

    companion object {
        const val CHANNEL_NAME = "schedule_plan/apk"

        /**
         * 当前活跃的通道。
         *
         * 安装结果是在 [InstallResultReceiver] 里拿到的，而它是被系统广播唤起的，
         * 拿不到 Activity 的引用。同一进程内用这个静态引用把结果捎回 Dart 是最直接
         * 的做法；Activity 销毁后引用还在，此时上报会失败，但那只影响"回执丢失"，
         * 下一次冷启动比对一下版本号就能纠正过来。
         */
        @Volatile
        private var activeChannel: MethodChannel? = null

        fun dispatchInstallResult(status: Int, message: String?) {
            activeChannel?.invokeMethod(
                "installResult",
                mapOf("status" to status, "message" to message),
            )
        }
    }
}
