import 'package:schedule_plan/core/constants/setting_keys.dart';
import 'package:schedule_plan/data/repositories/settings_repository.dart';
import 'package:schedule_plan/features/toolbox/focus/focus_controller.dart';

/// 把进行中的专注会话快照落在 `app_settings` 里。
///
/// 为什么值得专门落一份快照：手机上被系统回收太常见了 —— 尤其"锁屏放着
/// 不动、内存又紧"正是专注模式的标准用法。不落的话，用户专心坐了一小时
/// 回来看到的是一块归零的计时器，而这恰恰是最伤人的那一刻。
///
/// 存的是 `app_settings` 而不是新建一张表：这是**一台设备同一时刻只有一份**
/// 的临时状态，不是需要按行查询的历史记录，KV 表正合适。历史记录照旧写
/// `focus_session`（那是统计口径）。
class FocusSnapshotSettingsStore implements FocusSnapshotStore {
  FocusSnapshotSettingsStore(this._settings);

  final SettingsRepository _settings;

  @override
  Future<void> save(FocusSnapshot snapshot) =>
      _settings.write(SettingKeys.focusSessionSnapshot, snapshot.encode());

  @override
  Future<FocusSnapshot?> load() async => FocusSnapshot.tryParse(
        await _settings.read(SettingKeys.focusSessionSnapshot),
      );

  /// 用写空串而不是删行：`app_settings` 是 KV 表，留个空值比删行简单，
  /// 读取侧按 [FocusSnapshot.tryParse] 的空串分支返回 null。
  @override
  Future<void> clear() =>
      _settings.write(SettingKeys.focusSessionSnapshot, '');
}
