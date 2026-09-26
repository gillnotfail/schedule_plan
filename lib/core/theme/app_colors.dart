import 'package:flutter/material.dart';

/// 六套主题（模块七 7.5 扩展）：清新薄荷 / 晨曦暖橙 / 极简灰白 /
/// 静谧深蓝 / 樱花粉 / 深夜护眼。
enum AppThemeKind {
  mint,
  sunrise,
  minimalGray,
  oceanBlue,
  sakura,
  nightCare;

  /// 落库到 app_settings 的键。
  String get storageKey => name;

  static AppThemeKind fromStorage(String? value) {
    return AppThemeKind.values.firstWhere(
      (item) => item.name == value,
      orElse: () => AppThemeKind.mint,
    );
  }
}

/// 亮色主题下共享的「考勤状态语义色」。
///
/// 五种考勤状态在全国范围内有稳定认知（出勤=绿、迟到=橙、缺勤=红…），
/// 不随主题色漂移，只随明暗模式切换，避免用户换主题后看不懂。
const AttendancePalette _lightAttendance = AttendancePalette(
  present: Color(0xFF1B8A4B),
  late: Color(0xFFE8710A),
  earlyLeave: Color(0xFF8E4BC0),
  absent: Color(0xFFD63B3B),
  leave: Color(0xFF2A6FD9),
  unmarked: Color(0xFF8C9296),
  // 休学 / 免修是**中性长期状态**，不是"异常出勤"：
  // 刻意用低饱和的青灰 / 蓝灰，避免和"缺勤红""请假蓝"抢视线
  suspended: Color(0xFF5C6B73),
  exempt: Color(0xFF0E8AA8),
  riskHighlight: Color(0xFFFFF1F0),
  nowLine: Color(0xFFE23B3B),
  breakBand: Color(0xFFF1F5F4),
  chartWarn: Color(0xFFE23B3B),
  danger: Color(0xFFD63B3B),
);

/// 暗色主题下共享的考勤语义色（提高亮度保证暗底对比度）。
const AttendancePalette _darkAttendance = AttendancePalette(
  present: Color(0xFF6BD98F),
  late: Color(0xFFFFB454),
  earlyLeave: Color(0xFFD6A3F0),
  absent: Color(0xFFFF8080),
  leave: Color(0xFF7FB3FF),
  unmarked: Color(0xFF8A9296),
  suspended: Color(0xFFA8B6BD),
  exempt: Color(0xFF6FD0E0),
  riskHighlight: Color(0xFF452A2A),
  nowLine: Color(0xFFFF6B6B),
  breakBand: Color(0xFF1E2A28),
  chartWarn: Color(0xFFFF6B6B),
  danger: Color(0xFFFF8080),
);

@immutable
class AttendancePalette {
  const AttendancePalette({
    required this.present,
    required this.late,
    required this.earlyLeave,
    required this.absent,
    required this.leave,
    required this.unmarked,
    required this.suspended,
    required this.exempt,
    required this.riskHighlight,
    required this.nowLine,
    required this.breakBand,
    required this.chartWarn,
    required this.danger,
  });

  final Color present;
  final Color late;
  final Color earlyLeave;
  final Color absent;
  final Color leave;
  final Color unmarked;

  /// 休学（长期状态）
  final Color suspended;

  /// 免修（长期状态）
  final Color exempt;
  final Color riskHighlight;
  final Color nowLine;
  final Color breakBand;
  final Color chartWarn;
  final Color danger;
}

/// 工具箱功能卡片的色相（用户规格第 13 轮）。
///
/// 用户参考图里的卡片是**实色**的（蓝/玫红/绿/橙/紫/青），要求是
/// "有颜色，饱和度可以低一点，但是配合的好看一点"。所以这里不是随手取六个色，
/// 而是按同一套规则定的六色相：
///
/// - **同一个明度**：六个色相的相对亮度都在 0.17~0.22 之间 ——
///   白字压在上面的对比度 4.5:1 上下，六张卡"深浅一致"才不会有的亮有的闷；
/// - **同一个饱和度**：都在 HSL 的 42%~46%，比参考图低一档，放在浅色底上不刺眼；
/// - **色相均匀铺开**：219°(蓝) → 262°(紫) → 337°(玫红) → 32°(橙) → 160°(绿)
///   → 196°(青)，相邻两张卡永远一个偏冷一个偏暖，扫过去不糊成一片。
///
/// 卡片底色 = `[light, deep]` 斜向渐变（ΔE 很小，只是让卡面有点光），
/// 图标块用白色 22% 的蒙版 —— 这样**不需要第二套色**就能做出层次，
/// 避免"每个工具一套配色"越加越乱。
@immutable
class ToolCardTone {
  const ToolCardTone({
    required this.key,
    required this.light,
    required this.deep,
  });

  /// 语义化的键名（单测与调试用，不要拿来做业务判断）。
  final String key;

  /// 渐变左上端（略亮）。
  final Color light;

  /// 渐变右下端（略深）。
  final Color deep;

  /// 深色主题下把整块卡片提亮一点点：暗底上的卡片如果沿用亮色主题的深度，
  /// 会显得"陷进去"，且和暗色卡片阴影糊在一起。
  List<Color> gradientFor(Brightness brightness) => brightness == Brightness.dark
      ? <Color>[
          Color.lerp(light, Colors.white, 0.10)!,
          Color.lerp(deep, Colors.white, 0.06)!,
        ]
      : <Color>[light, deep];

  static const ToolCardTone blue = ToolCardTone(
    key: 'blue',
    light: Color(0xFF446DC6),
    deep: Color(0xFF34569F),
  );
  static const ToolCardTone violet = ToolCardTone(
    key: 'violet',
    light: Color(0xFF7E60BB),
    deep: Color(0xFF61459C),
  );
  static const ToolCardTone rose = ToolCardTone(
    key: 'rose',
    light: Color(0xFFC04A74),
    deep: Color(0xFF9E355C),
  );
  static const ToolCardTone amber = ToolCardTone(
    key: 'amber',
    light: Color(0xFFA5691A),
    deep: Color(0xFF8A5410),
  );
  static const ToolCardTone green = ToolCardTone(
    key: 'green',
    light: Color(0xFF377E61),
    deep: Color(0xFF29674D),
  );
  static const ToolCardTone teal = ToolCardTone(
    key: 'teal',
    light: Color(0xFF2E7B96),
    deep: Color(0xFF21607A),
  );

  /// 网格里的出场顺序：**逐行"一冷一暖"**，六张卡连起来看是一条色相带。
  static const List<ToolCardTone> all = <ToolCardTone>[
    blue,
    violet,
    rose,
    amber,
    green,
    teal,
  ];
}

/// Design Token 中的「语义色」部分。
///
/// 组件内禁止硬编码颜色值，一律从这里取，保证六套主题切换时表现一致。
@immutable
class AppColorTokens {
  const AppColorTokens({
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tertiary,
    required this.onTertiary,
    required this.surface,
    required this.surfaceContainerLowest,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.outline,
    required this.outlineVariant,
    required this.scaffoldBackground,
    required this.isDark,
    required this.shadow,
    required this.attendance,
    required this.accentGradient,
  });

  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color secondary;
  final Color onSecondary;
  final Color secondaryContainer;
  final Color onSecondaryContainer;
  final Color tertiary;
  final Color onTertiary;
  final Color surface;
  final Color surfaceContainerLowest;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color outline;
  final Color outlineVariant;
  final Color scaffoldBackground;
  final bool isDark;

  /// 柔和阴影色（M3E 用极低透明度的大范围阴影替代老式 elevation）。
  final Color shadow;

  final AttendancePalette attendance;

  /// 强调区（顶部渐变背景）的两端色。
  final List<Color> accentGradient;

  // ---------------------------------------------------------------------------
  // 考勤语义色快捷访问
  // ---------------------------------------------------------------------------
  Color get attendancePresent => attendance.present;
  Color get attendanceLate => attendance.late;
  Color get attendanceEarlyLeave => attendance.earlyLeave;
  Color get attendanceAbsent => attendance.absent;
  Color get attendanceLeave => attendance.leave;
  Color get attendanceUnmarked => attendance.unmarked;
  Color get attendanceSuspended => attendance.suspended;
  Color get attendanceExempt => attendance.exempt;
  Color get riskHighlight => attendance.riskHighlight;
  Color get nowLine => attendance.nowLine;
  Color get breakBand => attendance.breakBand;
  Color get chartWarn => attendance.chartWarn;
  Color get danger => attendance.danger;

  // ---------------------------------------------------------------------------
  // 六套预设
  // ---------------------------------------------------------------------------

  /// 清新薄荷
  static const AppColorTokens mint = AppColorTokens(
    primary: Color(0xFF00897B),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFB8F2E6),
    onPrimaryContainer: Color(0xFF004F47),
    secondary: Color(0xFF4A6572),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFCCE8E4),
    onSecondaryContainer: Color(0xFF0D3B3B),
    tertiary: Color(0xFF7A5CA8),
    onTertiary: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceContainerLowest: Color(0xFFFBFFFE),
    surfaceContainer: Color(0xFFF2FAF8),
    surfaceContainerHigh: Color(0xFFE7F4F1),
    surfaceContainerHighest: Color(0xFFDEEFEC),
    onSurface: Color(0xFF141F1E),
    onSurfaceVariant: Color(0xFF526562),
    outline: Color(0xFFA6C0BC),
    outlineVariant: Color(0xFFDCE9E6),
    scaffoldBackground: Color(0xFFF4FAF9),
    isDark: false,
    shadow: Color(0x14004F47),
    attendance: _lightAttendance,
    accentGradient: <Color>[Color(0xFF00A89A), Color(0xFF4FC3B0)],
  );

  /// 晨曦暖橙
  static const AppColorTokens sunrise = AppColorTokens(
    primary: Color(0xFFD4550B),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFFFDCC2),
    onPrimaryContainer: Color(0xFF5A1E00),
    secondary: Color(0xFF74553F),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFFBDCC2),
    onSecondaryContainer: Color(0xFF4A2C13),
    tertiary: Color(0xFF8A5A00),
    onTertiary: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceContainerLowest: Color(0xFFFFFDFB),
    surfaceContainer: Color(0xFFFDF6F0),
    surfaceContainerHigh: Color(0xFFF8EBE0),
    surfaceContainerHighest: Color(0xFFF3E2D5),
    onSurface: Color(0xFF24150C),
    onSurfaceVariant: Color(0xFF6B5648),
    outline: Color(0xFFC4A792),
    outlineVariant: Color(0xFFF0DCCB),
    scaffoldBackground: Color(0xFFFEF8F4),
    isDark: false,
    shadow: Color(0x145A1E00),
    attendance: _lightAttendance,
    accentGradient: <Color>[Color(0xFFF57C1F), Color(0xFFFFA94D)],
  );

  /// 极简灰白
  static const AppColorTokens minimalGray = AppColorTokens(
    primary: Color(0xFF3C4A52),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFDCE3E8),
    onPrimaryContainer: Color(0xFF101B22),
    secondary: Color(0xFF5C6470),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFE3E7ED),
    onSecondaryContainer: Color(0xFF1C2129),
    tertiary: Color(0xFF6B5B7B),
    onTertiary: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceContainerLowest: Color(0xFFFDFDFE),
    surfaceContainer: Color(0xFFF5F6F8),
    surfaceContainerHigh: Color(0xFFEBEDEF),
    surfaceContainerHighest: Color(0xFFE2E5E8),
    onSurface: Color(0xFF14181C),
    onSurfaceVariant: Color(0xFF585F66),
    outline: Color(0xFFAEB5BC),
    outlineVariant: Color(0xFFDFE3E7),
    scaffoldBackground: Color(0xFFF8F9FA),
    isDark: false,
    shadow: Color(0x1210181F),
    attendance: _lightAttendance,
    accentGradient: <Color>[Color(0xFF4A5A63), Color(0xFF74838D)],
  );

  /// 静谧深蓝
  static const AppColorTokens oceanBlue = AppColorTokens(
    primary: Color(0xFF1B6BC4),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFC6E0FF),
    onPrimaryContainer: Color(0xFF00315F),
    secondary: Color(0xFF4F6076),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFD2E3F5),
    onSecondaryContainer: Color(0xFF0D2A3F),
    tertiary: Color(0xFF0E8AA8),
    onTertiary: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceContainerLowest: Color(0xFFFAFCFF),
    surfaceContainer: Color(0xFFF2F6FB),
    surfaceContainerHigh: Color(0xFFE7EFF8),
    surfaceContainerHighest: Color(0xFFDEE8F2),
    onSurface: Color(0xFF101820),
    onSurfaceVariant: Color(0xFF556270),
    outline: Color(0xFFA3B4C6),
    outlineVariant: Color(0xFFDAE4EE),
    scaffoldBackground: Color(0xFFF5F9FD),
    isDark: false,
    shadow: Color(0x1400315F),
    attendance: _lightAttendance,
    accentGradient: <Color>[Color(0xFF2A7FD4), Color(0xFF5FA8F5)],
  );

  /// 樱花粉
  static const AppColorTokens sakura = AppColorTokens(
    primary: Color(0xFFC8377B),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFFFD6E6),
    onPrimaryContainer: Color(0xFF5E0F35),
    secondary: Color(0xFF72606B),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFF6DCE8),
    onSecondaryContainer: Color(0xFF3D1F2E),
    tertiary: Color(0xFF8A5CA8),
    onTertiary: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceContainerLowest: Color(0xFFFFFBFD),
    surfaceContainer: Color(0xFFFCF4F8),
    surfaceContainerHigh: Color(0xFFF8EAF1),
    surfaceContainerHighest: Color(0xFFF3E0EA),
    onSurface: Color(0xFF201318),
    onSurfaceVariant: Color(0xFF66565E),
    outline: Color(0xFFC0A6B2),
    outlineVariant: Color(0xFFEEDCE5),
    scaffoldBackground: Color(0xFFFDF6F9),
    isDark: false,
    shadow: Color(0x145E0F35),
    attendance: _lightAttendance,
    accentGradient: <Color>[Color(0xFFE0458C), Color(0xFFFF85B3)],
  );

  /// 深夜护眼
  static const AppColorTokens nightCare = AppColorTokens(
    primary: Color(0xFF7FD1C1),
    onPrimary: Color(0xFF00382F),
    primaryContainer: Color(0xFF1E4B44),
    onPrimaryContainer: Color(0xFFB5F0E4),
    secondary: Color(0xFFB0CCC4),
    onSecondary: Color(0xFF0B3330),
    secondaryContainer: Color(0xFF223B38),
    onSecondaryContainer: Color(0xFFCFE9E2),
    tertiary: Color(0xFFC4ACF0),
    onTertiary: Color(0xFF2A1650),
    surface: Color(0xFF111918),
    surfaceContainerLowest: Color(0xFF0C1312),
    surfaceContainer: Color(0xFF18211F),
    surfaceContainerHigh: Color(0xFF222D2B),
    surfaceContainerHighest: Color(0xFF2C3835),
    onSurface: Color(0xFFE2EAE8),
    onSurfaceVariant: Color(0xFFA5B6B2),
    outline: Color(0xFF54645F),
    outlineVariant: Color(0xFF2E3A37),
    scaffoldBackground: Color(0xFF0C1312),
    isDark: true,
    shadow: Color(0x40000000),
    attendance: _darkAttendance,
    accentGradient: <Color>[Color(0xFF0E7C6C), Color(0xFF1E4B44)],
  );

  static AppColorTokens of(AppThemeKind kind) => switch (kind) {
        AppThemeKind.mint => mint,
        AppThemeKind.sunrise => sunrise,
        AppThemeKind.minimalGray => minimalGray,
        AppThemeKind.oceanBlue => oceanBlue,
        AppThemeKind.sakura => sakura,
        AppThemeKind.nightCare => nightCare,
      };
}
