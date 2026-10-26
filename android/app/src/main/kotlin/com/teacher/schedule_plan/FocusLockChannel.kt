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

            // 尝试进入屏幕固定。返回三态（见下面 ENTER_* 常量）：
            // 0 = 拿不到，1 = 已锁定，2 = 请求已发出、但系统还在等用户确认。
            // **不能只回 true/false** —— 首次进入「屏幕固定」系统会弹确认框，
            // 那一刻状态仍是 NONE，回 false 会让 Dart 侧记成"没锁上"，
            // 结果到点释放时被跳过，App 就被系统钉死退不出去了。
            "enterLockTask" -> result.success(enterLockTask())

            // 返回**是否确认已解除**。Dart 侧拿 false 会再补一次调用。
            "exitLockTask" -> result.success(exitLockTask())

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

    /**
     * 进入屏幕固定，返回 [ENTER_LOCKED] / [ENTER_PENDING] / [ENTER_UNSUPPORTED]。
     *
     * 区分 PENDING 是这套代码的关键：`startLockTask()` 正常返回不代表已经锁上。
     * 用户第一次用「屏幕固定」时，系统会弹一个"要固定此应用吗"的确认框，
     * 点确认之前 `lockTaskModeState` 还是 NONE。如果把这种"待确认"当成失败，
     * 用户随后点了确认就真的锁上了，而 App 以为自己没锁 → 结束时不释放 →
     * **整个 App 被系统钉住，退不出去**。
     */
    private fun enterLockTask(): Int {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            mainHandler.post { doEnterLockTask() }
            return ENTER_PENDING
        }
        return doEnterLockTask()
    }

    private fun doEnterLockTask(): Int {
        if (currentLockTaskState() != LOCK_TASK_MODE_NONE) {
            return ENTER_LOCKED
        }
        return try {
            activity.startLockTask()
            if (currentLockTaskState() != LOCK_TASK_MODE_NONE) {
                ENTER_LOCKED
            } else {
                // 没抛异常也没进锁定态：要么系统正在等用户确认，要么这台 ROM
                // 把「屏幕固定」阉割了（不少国产 ROM 如此）。两者都算"请求过"，
                // 释放时必须照样去 stop 一次，否则就是上面说的死局。
                ENTER_PENDING
            }
        } catch (error: Throwable) {
            ENTER_UNSUPPORTED
        }
    }

    /**
     * 退出屏幕固定，返回**是否确认已解除**。
     *
     * 这里刻意**不看前置状态再决定要不要停** —— 之前的写法是"读到 NONE 就
     * 直接 return"，可一旦读状态本身失败（部分 ROM 会），就再也不会去 stop，
     * 而屏幕上确实还钉着。宁可多调一次 `stopLockTask()`（不在锁定态时它会
     * 抛 IllegalStateException，吞掉即可），也不能漏掉。
     */
    private fun exitLockTask(): Boolean {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            mainHandler.post { doExitLockTask() }
            return true
        }
        doExitLockTask()
        if (currentLockTaskState() == LOCK_TASK_MODE_NONE) {
            return true
        }
        // stopLockTask 不是秒生效的：等一小会儿再看，还在锁定就再停一次。
        // 这是"退不出去"的最后一道保险。
        mainHandler.postDelayed({ doExitLockTask() }, EXIT_RETRY_DELAY_MS)
        return false
    }

    private fun doExitLockTask() {
        try {
            activity.stopLockTask()
        } catch (error: Throwable) {
            // 当前并不在锁定态时 stop 会抛 IllegalStateException，属于正常情况。
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

    /**
     * Activity 销毁时释放：提示音通道 + **残留的屏幕固定**。
     *
     * 后一件事是兜底：正常路径下专注页退出会主动释放，但只要有一环没走到
     * （Flutter 侧异常、后台被杀前那一刻），用户下次打开就是个钉死的 App。
     * 这里再补一刀，成本接近零。
     */
    fun dispose() {
        mainHandler.post {
            toneGenerator?.release()
            toneGenerator = null
        }
        if (currentLockTaskState() != LOCK_TASK_MODE_NONE) {
            doExitLockTask()
        }
    }

    companion object {
        private const val CHANNEL_NAME = "schedule_plan/focus_lock"

        /** 对应 `ActivityManager.LOCK_TASK_MODE_NONE`。 */
        private const val LOCK_TASK_MODE_NONE = 0

        /** [enterLockTask] 三态：拿不到 / 已锁定 / 请求已发出待确认。 */
        private const val ENTER_UNSUPPORTED = 0
        private const val ENTER_LOCKED = 1
        private const val ENTER_PENDING = 2

        /** stopLockTask 不是秒生效，隔一小会儿再确认一次。 */
        private const val EXIT_RETRY_DELAY_MS = 300L
    }
}
