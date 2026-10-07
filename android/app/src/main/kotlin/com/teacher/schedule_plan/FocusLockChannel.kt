package com.teacher.schedule_plan

import android.app.Activity
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 专注模式所需的原生能力：屏幕常亮、系统「屏幕固定」、提示音。
 *
 * 三件事都刻意**不引第三方依赖**：
 * - 常亮用 `FLAG_KEEP_SCREEN_ON`（系统窗口标志，不需要权限）；
 * - 锁屏用 Activity 自带的 `startLockTask()`（系统「屏幕固定」，不需要权限）；
 * - 提示音用系统自带的 [ToneGenerator]（不需要音频资源文件，APK 一点不涨）。
 *
 * 关于「绝对锁定」这件事必须说清楚：**普通 App 做不到**。真正的 kiosk
 * 要求设备所有者（Device Owner），得用 adb 把手机设成受管设备，普通老师
 * 自己完不成。App 层面能拿到的最强档位就是系统的「屏幕固定」——把通知栏、
 * 最近任务、回桌面全部锁死，只留系统自己的「长按返回 + 最近任务」退出。
 * 而且它要用户先在系统设置里打开「屏幕固定」，不少国产 ROM 还把它藏了
 * 或者阉割掉，所以这里 `enterLockTask()` 一律**先做后验**：
 * 调完立刻读一次真实状态，没进去就如实返回 false，让界面告诉用户原因，
 * 而不是显示一个"已锁定"的假象。
 */
class FocusLockChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL_NAME).apply {
        setMethodCallHandler(this@FocusLockChannel)
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    /** 复用一个 ToneGenerator：每次新建会有几十毫秒延迟，听起来像卡了一下。 */
    private var toneGenerator: ToneGenerator? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setKeepScreenOn" -> {
                val enabled = call.arguments as? Boolean ?: false
                setKeepScreenOn(enabled)
                result.success(null)
            }

            // 0 = 未进入，1 = 屏幕固定，2 = 设备所有者锁定。
            "lockTaskState" -> result.success(currentLockTaskState())

            // 尝试进入屏幕固定。返回的是**调用之后立刻读到的真实状态**，
            // 而不是"我调了所以应该成功了"。
            "enterLockTask" -> {
                enterLockTask()
                result.success(currentLockTaskState() != LOCK_TASK_MODE_NONE)
            }

            "exitLockTask" -> {
                exitLockTask()
                result.success(null)
            }

            "playCue" -> {
                playCue(call.arguments as? String ?: "")
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    // -------------------------------------------------------------------------
    // 屏幕常亮
    // -------------------------------------------------------------------------

    private fun setKeepScreenOn(enabled: Boolean) {
        // 必须在 UI 线程改窗口标志。
        activity.runOnUiThread {
            if (enabled) {
                activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            } else {
                activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
        }
    }

    // -------------------------------------------------------------------------
    // 屏幕固定（系统锁任务）
    // -------------------------------------------------------------------------

    private fun currentLockTaskState(): Int {
        val manager = activity.getSystemService(Activity.ACTIVITY_SERVICE) as? android.app.ActivityManager
            ?: return LOCK_TASK_MODE_NONE
        return try {
            manager.lockTaskModeState
        } catch (error: Throwable) {
            LOCK_TASK_MODE_NONE
        }
    }

    private fun enterLockTask() {
        if (currentLockTaskState() != LOCK_TASK_MODE_NONE) {
            return
        }
        activity.runOnUiThread {
            try {
                // 没开「屏幕固定」时这个方法不会抛异常，只是不生效 ——
                // 所以返回给 Dart 的是"调完再读一次"的结果，不是 true。
                activity.startLockTask()
            } catch (error: Throwable) {
                // 部分 ROM 会直接抛 IllegalStateException，吞掉当作"不支持"。
            }
        }
    }

    private fun exitLockTask() {
        if (currentLockTaskState() == LOCK_TASK_MODE_NONE) {
            return
        }
        activity.runOnUiThread {
            try {
                activity.stopLockTask()
            } catch (error: Throwable) {
                // 已经不在锁定态时 stop 会抛，忽略。
            }
        }
    }

    // -------------------------------------------------------------------------
    // 提示音
    // -------------------------------------------------------------------------

    /**
     * 按用途挑一个系统音。走 [AudioManager.STREAM_NOTIFICATION] 而不是 ALARM，
     * 这样**静音模式真的会静音** —— 在教室或办公室里，安静比响亮重要。
     */
    private fun playCue(kind: String) {
        val tone = when (kind) {
            "start", "resume" -> ToneGenerator.TONE_PROP_BEEP
            "pause" -> ToneGenerator.TONE_PROP_ACK
            "halfway" -> ToneGenerator.TONE_PROP_BEEP2
            "lastMinute" -> ToneGenerator.TONE_PROP_BEEP2
            "finish" -> ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD
            else -> return
        }
        val durationMs = if (kind == "finish") 600 else 180
        mainHandler.post {
            try {
                val generator = toneGenerator ?: ToneGenerator(AudioManager.STREAM_NOTIFICATION, 80)
                    .also { toneGenerator = it }
                generator.startTone(tone, durationMs)
            } catch (error: Throwable) {
                // 个别设备上声道被占用会抛，提示音失败不该影响计时。
            }
        }
    }

    /** 页面退出时释放，避免 ToneGenerator 一直占着音频通道。 */
    fun dispose() {
        mainHandler.post {
            toneGenerator?.release()
            toneGenerator = null
        }
    }

    companion object {
        private const val CHANNEL_NAME = "schedule_plan/focus_lock"

        /** 对应 `ActivityManager.LOCK_TASK_MODE_NONE`。 */
        private const val LOCK_TASK_MODE_NONE = 0
    }
}
