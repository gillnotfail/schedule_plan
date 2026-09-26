package com.teacher.schedule_plan

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build

/**
 * 接收系统安装器的结果回执。
 *
 * 安装不是"发一个 Intent 就完事"：`PackageInstaller.commit()` 之后，
 * 系统要么让用户点确认（STATUS_PENDING_USER_ACTION，此时会在
 * [Intent.EXTRA_INTENT] 里附带确认界面），要么直接给结果。
 * 用户确认完还会再来一次广播。所以这个接收器会被调用 **一到两次**：
 *   1. 先收到 PENDING_USER_ACTION → 我们把确认界面拉起来；
 *   2. 用户点完"安装" → 再收到 SUCCESS / FAILURE。
 * 两次都往上汇报，Dart 侧据此区分"等待用户确认"和"真的装好了"。
 */
class InstallResultReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(
            PackageInstaller.EXTRA_STATUS,
            PackageInstaller.STATUS_FAILURE,
        )
        val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)

        if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            launchConfirmDialog(context, intent)
        }
        ApkInstallerChannel.dispatchInstallResult(status, message)
    }

    /** 把系统安装器的确认界面拉起来。拉不起来也不能崩，只是这次安装作废。 */
    private fun launchConfirmDialog(context: Context, intent: Intent) {
        val confirm = confirmIntentOf(intent) ?: return
        confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            context.startActivity(confirm)
        } catch (error: Throwable) {
            // 少数 ROM 会拦这个界面，此时用户什么也看不到，
            // 但下次点"更新"还能再来一遍，不需要额外补救。
        }
    }

    private fun confirmIntentOf(intent: Intent): Intent? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_INTENT) as? Intent
        }
}
