import 'package:flutter/services.dart';

import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/features/toolbox/focus/focus_controller.dart';

/// 尝试进入「屏幕固定」的结果。
///
/// **必须有 [pending] 这一档**：首次使用时系统会弹"要固定此应用吗"的确认框，
/// 点确认之前原生那边读到的状态还是"未锁定"。若把这种情况当成 [unsupported]，
/// 页面就会以为没锁上，到点释放时跳过 `stopLockTask()` —— 用户随后点了确认，
/// 于是真的锁着，而 App 已经不打算再释放它，整个 App 被钉死退不出去。
enum FocusLockStatus {
  /// 这台机器拿不到（没开「屏幕固定」，或 ROM 阉割了）。
  unsupported,

  /// 已经在锁定态。
  locked,

  /// 请求已发出，但系统还在等用户确认（或静默不生效）。
  /// 释放时必须照样去 stop。
  pending,
}

/// 专注模式的原生能力封装（原生实现在
/// `android/app/src/main/kotlin/com/teacher/schedule_plan/FocusLockChannel.kt`）。
///
/// 三件事：屏幕常亮、系统「屏幕固定」、提示音。
///
/// **为什么不做「绝对锁定」**：Android 上真正的 kiosk 需要设备所有者
/// （Device Owner），得用 adb 把手机设成受管设备 —— 普通老师自己完不成，
/// 在教师机上不现实。App 层面能做到的最强档位是系统的「屏幕固定」
/// （`startLockTask`），它能锁死通知栏 / 最近任务 / 回桌面。所以这里按
/// **两档**设计：
/// - 默认档：沉浸全屏 + 常亮 + 拦返回，任何手机都能用；
/// - 增强档：额外尝试屏幕固定，**先做后验**，没成功就如实上报。
///
/// 所有方法在非 Android 平台（桌面调试、单测）安全降级：
/// 通道不存在时返回"不支持"，绝不抛异常把页面打崩。
class FocusLockService {
  FocusLockService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  /// 通道名。Dart 与 Kotlin 两侧必须一致。
  static const String channelName = 'schedule_plan/focus_lock';

  final MethodChannel _channel;

  /// 屏幕常亮开关。专注结束 / 暂停 / 页面退出时必须关掉 ——
  /// 忘了关就是"退出专注后手机再也不息屏"，用户会以为是手机坏了。
  Future<void> setKeepScreenOn(bool enabled) =>
      _invoke<void>('setKeepScreenOn', null, arguments: enabled);

  /// 当前是否处在系统锁定态（屏幕固定 / 设备所有者锁定）。
  Future<bool> isLocked() async =>
      (await _lockTaskState()) != _lockTaskModeNone;

  /// 尝试进入屏幕固定。**返回值是调用之后真实读到的状态**，
  /// 见 [FocusLockStatus] 对 [FocusLockStatus.pending] 的说明。
  Future<FocusLockStatus> enterLockTask() async {
    final code = await _invoke<int>('enterLockTask', _enterUnsupported);
    return switch (code) {
      _enterLocked => FocusLockStatus.locked,
      _enterPending => FocusLockStatus.pending,
      _ => FocusLockStatus.unsupported,
    };
  }

  /// 退出屏幕固定，返回**是否确认已解除**。
  ///
  /// 失败时页面会再补一次调用；非 Android 环境返回 true（当作无需释放），
  /// 免得在桌面调试时反复重试。
  Future<bool> exitLockTask() => _invoke<bool>('exitLockTask', true);

  /// 发一次提示音。
  Future<void> playCue(FocusCue cue) =>
      _invoke<void>('playCue', null, arguments: cue.name);

  Future<int> _lockTaskState() =>
      _invoke<int>('lockTaskState', _lockTaskModeNone);

  Future<T> _invoke<T>(
    String method,
    T fallback, {
    Object? arguments,
  }) async {
    try {
      final result = await _channel.invokeMethod<T>(method, arguments);
      return result ?? fallback;
    } on MissingPluginException {
      // 桌面端与单测环境没有这个通道，属于预期内，不必记日志。
      return fallback;
    } on PlatformException catch (error, stack) {
      AppLogger.w('专注锁定通道 $method 调用失败：${error.message}');
      AppLogger.e('专注锁定通道异常', error: error, stack: stack);
      return fallback;
    }
  }

  /// 对应 `ActivityManager.LOCK_TASK_MODE_NONE`。
  static const int _lockTaskModeNone = 0;

  /// 与原生 `ENTER_UNSUPPORTED / ENTER_LOCKED / ENTER_PENDING` 一一对应。
  static const int _enterUnsupported = 0;
  static const int _enterLocked = 1;
  static const int _enterPending = 2;
}
