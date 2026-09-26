import 'dart:io';

import 'package:flutter/services.dart';

import 'package:schedule_plan/core/logging/app_logger.dart';

/// Android 侧安装相关能力的通道封装（原生实现在
/// `android/app/src/main/kotlin/com/teacher/schedule_plan/ApkInstallerChannel.kt`）。
///
/// 为什么走 `PackageInstaller` 而不是 `Intent.ACTION_VIEW` + FileProvider
/// ----------------------------------------------------------------
/// 后者需要把 APK 暴露成 `content://` URI 交给系统安装器，于是必须额外
/// 声明一个 FileProvider 并依赖 `androidx.core`（本项目的 FileProvider 是
/// 由 share_plus 带进来的，直接 import 等于把编译期正确性押在别人的
/// 依赖可见性上）。`PackageInstaller` 走的是"把字节写进安装会话管道"，
/// **根本不需要 URI**，顺带还能拿到安装结果回调，因此这里选它。
///
/// 所有方法在非 Android 平台（桌面调试、单测）都会安全降级：
/// 通道不存在时返回"不支持"，而不是抛异常把页面打崩。
class ApkInstaller {
  ApkInstaller({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  /// 通道名。Dart 与 Kotlin 两侧必须一致。
  static const String channelName = 'schedule_plan/apk';

  /// 安装结果回执的方法名（由原生主动回调上来）。
  static const String resultMethod = 'installResult';

  final MethodChannel _channel;

  /// 安装结果回调。原生完成或失败后触发一次。
  void Function(ApkInstallOutcome outcome)? onInstallResult;

  bool _handlerBound = false;

  void _ensureHandler() {
    if (_handlerBound) {
      return;
    }
    _handlerBound = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != resultMethod) {
        return null;
      }
      final args = call.arguments;
      if (args is! Map) {
        return null;
      }
      onInstallResult?.call(
        ApkInstallOutcome(
          status: (args['status'] as num?)?.toInt() ?? -1,
          message: args['message'] as String?,
        ),
      );
      return null;
    });
  }

  /// 正在运行的这个 App 自己的 APK 路径（`/data/app/.../base.apk`）。
  ///
  /// 分差升级要拿它当基础包——**用的必须就是设备上正在跑的那份字节**，
  /// 拿发布包去当基准是不对的（用户装的可能是别的渠道、或被系统改写过）。
  Future<String?> installedApkPath() =>
      _invoke<String?>('installedApkPath', null);

  /// 可写的工作目录（原生会确保它存在）。下载的补丁与合成出的新包都放这里。
  ///
  /// 目录由原生给出而不是 Dart 侧用 path_provider 猜：Android 上
  /// `getApplicationSupportDirectory` / `getApplicationDocumentsDirectory`
  /// 到底映射到哪个目录是有版本差异的，写偏了原生侧就读不到。
  Future<String?> prepareWorkDir() => _invoke<String?>('prepareWorkDir', null);

  /// 是否已获准「安装未知应用」。未获准就调起安装只会白失败一次。
  Future<bool> canInstallPackages() =>
      _invoke<bool>('canInstallPackages', false);

  /// 跳到本应用的「安装未知应用」授权页。
  ///
  /// 没有返回值可退，所以单独实现而不是走 [_invoke]——
  /// 后者靠"取不到就用兜底值"来容错，对 void 没有意义。
  Future<void> openInstallPermissionSettings() async {
    try {
      await _channel.invokeMethod<void>('openInstallPermissionSettings');
    } on MissingPluginException {
      // 桌面端与单测环境没有这个通道，属于预期内。
    } on PlatformException catch (error, stack) {
      AppLogger.w('打开安装授权页失败：${error.message}');
      AppLogger.e('打开安装授权页异常', error: error, stack: stack);
    }
  }

  /// 工作目录所在分区的剩余空间（字节）。用于提前拦下"空间不够"。
  Future<int> freeDiskBytes() => _invoke<int>('freeDiskBytes', 0);

  /// 把已经准备好的新包交给系统安装。
  ///
  /// 调用后不会立刻有结果——系统弹确认框、用户点安装、系统校验签名，
  /// 全过程走完才通过 [onInstallResult] 回执。所以这里只负责"交出去"。
  Future<bool> install(String apkPath) async {
    _ensureHandler();
    return _invoke<bool>(
      'install',
      false,
      arguments: <String, dynamic>{'path': apkPath},
    );
  }

  Future<T> _invoke<T>(
    String method,
    T fallback, {
    Map<String, dynamic>? arguments,
  }) async {
    try {
      final result = await _channel.invokeMethod<T>(method, arguments);
      return result ?? fallback;
    } on MissingPluginException {
      // 桌面端与单测环境没有这个通道，属于预期内，不必记日志。
      return fallback;
    } on PlatformException catch (error, stack) {
      AppLogger.w('安装通道 $method 调用失败：${error.message}');
      AppLogger.e('安装通道异常', error: error, stack: stack);
      return fallback;
    }
  }
}

/// 安装结果回执。
class ApkInstallOutcome {
  const ApkInstallOutcome({required this.status, this.message});

  /// 对应 Android `PackageInstaller.STATUS_*`，方便排查。
  final int status;
  final String? message;

  /// `PackageInstaller.STATUS_SUCCESS`
  bool get isSuccess => status == 0;

  /// 用户在系统确认框上取消了。
  bool get isCancelled => status == 2 || status == 3;

  @override
  String toString() => 'ApkInstallOutcome(status: $status, message: $message)';
}

/// 判断当前平台是否支持应用内自更新。
///
/// 只有 Android 有"覆盖安装"这回事；iOS / 桌面即使能下到包也装不上去，
/// 界面上应该直接不显示这条入口，而不是让用户点出一个失败的流程。
bool get supportsInAppUpdate => Platform.isAndroid;
