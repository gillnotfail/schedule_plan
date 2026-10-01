import 'package:flutter/foundation.dart';

/// 「去点名」请求：课表页点已有课程的格子 → 考勤页定位到这一节。
///
/// 用值对象而不是直接传 Widget/路由，是因为课表页与考勤页是
/// [IndexedStack] 里的两个平级 Tab，不存在 Navigator 的 push 关系，
/// 只能靠一份共享状态来"投递"跳转意图。
@immutable
class AttendanceRequest {
  const AttendanceRequest({
    required this.lessonId,
    required this.classId,
    required this.weekday,
    required this.date,
  });

  /// 目标课表条目（lesson.id）
  final int lessonId;

  /// 上这节课的班级
  final int classId;

  /// 1 = 周一 ... 7 = 周日
  final int weekday;

  /// 定位到的日期，格式 "YYYY-MM-DD"
  final String date;
}

/// 应用级导航状态：底部 Tab 切换 + 跨 Tab 跳转意图。
///
/// readme 的模块划分里课表页是首页，但"点名"这件事发生在考勤页，
/// 所以需要一层很薄的共享状态把两个页面接起来：
/// - [switchTab] 让任意页面把用户送到另一个 Tab；
/// - [openAttendance] 在切 Tab 的同时带上"要看哪节课"的意图，
///   考勤页消费（[consumeAttendance]）后自行定位，避免重复触发。
class AppNavigationState extends ChangeNotifier {
  /// 课表 / 考勤 / 工具箱 / 设置，与 [MainShell] 的 NavigationBar 顺序一致。
  static const int scheduleTabIndex = 0;
  static const int attendanceTabIndex = 1;
  static const int toolboxTabIndex = 2;

  int _tabIndex = scheduleTabIndex;
  int get tabIndex => _tabIndex;

  AttendanceRequest? _pendingAttendance;
  AttendanceRequest? get pendingAttendance => _pendingAttendance;

  /// 切换底部 Tab。
  void switchTab(int index) {
    if (_tabIndex == index) {
      return;
    }
    _tabIndex = index;
    notifyListeners();
  }

  /// 跳到考勤页并定位到指定课表条目。
  void openAttendance(AttendanceRequest request) {
    _pendingAttendance = request;
    _tabIndex = attendanceTabIndex;
    notifyListeners();
  }

  /// 考勤页处理完定位请求后清空，保证同一个请求只生效一次。
  void consumeAttendance() {
    if (_pendingAttendance == null) {
      return;
    }
    _pendingAttendance = null;
  }
}
