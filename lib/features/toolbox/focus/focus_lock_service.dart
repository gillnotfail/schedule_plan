import 'package:flutter/services.dart';

import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/features/toolbox/focus/focus_controller.dart';

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

  /// 尝试进入屏幕固定。**返回值是调用之后真实读到的状态**。
  ///
  /// 返回 false 的两种原因要分清：系统没开「屏幕固定」，或这台 ROM 不支持。
  /// 页面据此提示用户，而不是假装已经锁上了。
  Future<bool> enterLockTask() => _invoke<bool>('enterLockTask', false);

  /// 退出屏幕固定。已经在外面时调用无副作用。
  Future<void> exitLockTask() => _invoke<void>('exitLockTask', null);

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
}
