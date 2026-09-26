import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'package:schedule_plan/core/error/app_exceptions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';

/// 本地通知服务（readme 模块七 7.1 / 7.2 / 7.3）。
///
/// 不依赖云推送，全部为本地定时通知。
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const String _channelId = 'schedule_plan_reminder';
  static const String _channelName = '课前与日程提醒';
  static const String _channelDescription = '课表课前提醒与日程安排提醒';

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  bool get isInitialized => _initialized;

  /// 初始化时区数据库与通知插件。
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    try {
      tz_data.initializeTimeZones();
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const settings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );
      await _plugin.initialize(settings: settings);
      _initialized = true;
      AppLogger.i('本地通知服务已初始化');
    } catch (error, stack) {
      AppLogger.e('本地通知服务初始化失败', error: error, stack: stack);
      throw AppException('本地通知服务初始化失败：$error', cause: error);
    }
  }

  /// 请求通知权限（模块七 7.3：首次需要发送通知前主动请求）。
  Future<bool> requestPermission() async {
    await initialize();
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        final granted = await android?.requestNotificationsPermission();
        // Android 12 及以下无需运行时授权，插件可能返回 null，此时视为已授权
        return granted ?? true;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final ios = _plugin
            .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
        final granted = await ios?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        return granted ?? false;
      }
      return true;
    } catch (error, stack) {
      AppLogger.e('请求通知权限失败', error: error, stack: stack);
      return false;
    }
  }

  /// 检查当前权限状态（设置页「检查权限状态」入口）。
  Future<bool> checkPermission() async {
    await initialize();
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        return await android?.areNotificationsEnabled() ?? true;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final ios = _plugin
            .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
        final result = await ios?.checkPermissions();
        return result?.isEnabled ?? false;
      }
      return true;
    } catch (error, stack) {
      AppLogger.e('检查通知权限失败', error: error, stack: stack);
      return false;
    }
  }

  /// 权限被拒绝时跳转系统设置页，而不是仅文字提示（readme 第六章）。
  Future<void> openSystemSettings() async {
    try {
      await AppSettings.openAppSettings(type: AppSettingsType.notification);
    } catch (error, stack) {
      AppLogger.e('跳转系统通知设置页失败', error: error, stack: stack);
    }
  }

  NotificationDetails get _details => const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      );

  /// 安排一条定时通知。触发时刻由调用方**实时联查模板**计算得出。
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async {
    await initialize();
    try {
      final scheduled = tz.TZDateTime.from(when, tz.local);
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduled,
        notificationDetails: _details,
        payload: payload,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    } catch (error, stack) {
      AppLogger.e('安排通知失败（id=$id）', error: error, stack: stack);
    }
  }

  Future<void> cancel(int id) async {
    if (!_initialized) {
      return;
    }
    try {
      await _plugin.cancel(id: id);
    } catch (error, stack) {
      AppLogger.e('取消通知失败（id=$id）', error: error, stack: stack);
    }
  }

  /// 取消全部待发通知（重新生成提醒前调用）。
  Future<void> cancelAll() async {
    if (!_initialized) {
      return;
    }
    try {
      await _plugin.cancelAll();
    } catch (error, stack) {
      AppLogger.e('取消全部通知失败', error: error, stack: stack);
    }
  }

  /// 立即展示一条通知（用于调试与权限自检）。
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
  }) async {
    await initialize();
    try {
      await _plugin.show(id: id, title: title, body: body, notificationDetails: _details);
    } catch (error, stack) {
      AppLogger.e('展示通知失败', error: error, stack: stack);
    }
  }
}
