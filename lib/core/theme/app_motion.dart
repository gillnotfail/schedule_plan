import 'package:flutter/animation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// M3 Expressive 动效 Token。
///
/// 设计依据（Material 3 Expressive）：
/// - **Spatial Spring** 用于位移/布局变化，带弹性回弹；
/// - **Effects Spring** 用于颜色/透明度/缩放等非空间属性，平滑无过冲。
///
/// 全局禁止再出现裸写 `Duration(milliseconds: 200)` 这类魔法值，
/// 一律从这里取，保证整套 App 的节奏统一。
abstract final class AppMotion {
  // ---------------------------------------------------------------------------
  // 曲线
  // ---------------------------------------------------------------------------

  /// The Expressive Curve：M3E 的标志性过冲曲线（Spatial Spring）。
  ///
  /// 用于进入动画、卡片展开、Tab 指示器位移等「看得见的位移」。
  static const Curve expressive = Cubic(0.34, 1.56, 0.64, 1);

  /// 强回弹（Spatial Spring），用于高情绪价值的反馈（如解锁成就、完成打卡）。
  static const Curve elastic = Curves.elasticOut;

  /// 轻微回弹，用于按压缩放这类小位移，避免过冲过头显得廉价。
  static const Curve softSpring = Cubic(0.2, 1.25, 0.4, 1);

  /// Effects Spring：颜色、透明度、缩放过渡。
  static const Curve effects = Curves.easeInOutCubic;

  /// 纯进入（无过冲），用于列表项淡入。
  static const Curve enter = Curves.easeOutCubic;

  /// 纯退出，用于页面退场。
  static const Curve exit = Curves.easeInCubic;

  /// 减速，用于拖拽跟手后的惯性收敛。
  static const Curve decelerate = Curves.decelerate;

  // ---------------------------------------------------------------------------
  // 时长
  // ---------------------------------------------------------------------------

  /// 触摸反馈：按下缩小到 96% 的视觉响应时长（规范 3 要求约 100ms）。
  static const Duration instant = Duration(milliseconds: 100);

  /// 小控件状态切换（开关、Chip 选中）。
  static const Duration quick = Duration(milliseconds: 180);

  /// 滚轮选择器停止后的刻度吸附（模块一 1.6：建议 200ms）。
  static const Duration wheelSnap = Duration(milliseconds: 200);

  /// 停止滚动到判定「真的停住了」的静默窗口。
  ///
  /// 用来区分「手指抬起的惯性滚动中」与「已经停下」，
  /// 不属于视觉动效，所以比 [instant] 还短。
  static const Duration scrollSettle = Duration(milliseconds: 120);

  /// 标准过渡（折叠展开、主题色渐变）。
  static const Duration standard = Duration(milliseconds: 300);

  /// 空间弹簧：中等位移（BottomSheet、对话框）。
  static const Duration springMedium = Duration(milliseconds: 500);

  /// 空间弹簧：大位移（整页转场、分页切换）。
  static const Duration springSlow = Duration(milliseconds: 700);

  /// 页面转场总时长。
  static const Duration pageTransition = Duration(milliseconds: 420);

  /// 列表项错峰入场的相邻间隔。
  static const Duration listStaggerStep = Duration(milliseconds: 45);

  /// 列表入场总时长上限（超出后不再累加，避免长列表尾部等太久）。
  static const Duration listStaggerCap = Duration(milliseconds: 600);

  /// 表盘指针旋转。
  static const Duration dialPointer = Duration(milliseconds: 620);

  /// 成功/成就类脉冲动画周期。
  static const Duration pulse = Duration(milliseconds: 1400);

  /// 计算第 [index] 项的错峰延迟，并在超过上限后截断。
  static Duration staggerFor(int index) {
    final ms = index * listStaggerStep.inMilliseconds;
    if (ms >= listStaggerCap.inMilliseconds) {
      return listStaggerCap;
    }
    return Duration(milliseconds: ms);
  }

  /// 结合 [HapticFeedback] 的统一触觉反馈入口。
  ///
  /// M3E 规范：视觉运动必须与触觉协同（Meaningful Feedback）。
  static void tap() => HapticFeedback.lightImpact();

  /// 较重的反馈，用于确认/完成类操作。
  static void confirm() => HapticFeedback.mediumImpact();

  /// 选择类反馈（滚轮、分段切换）。
  static void select() => HapticFeedback.selectionClick();

  /// 拒绝/错误反馈。
  static void reject() => HapticFeedback.heavyImpact();
}
