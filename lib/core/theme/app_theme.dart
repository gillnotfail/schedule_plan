import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/theme/app_colors.dart';

/// 由 Design Token 构建 ThemeData（Material 3 Expressive）。
///
/// 三条硬规则：
/// 1. 颜色一律来自 [AppColorTokens]，组件内不得硬编码颜色；
/// 2. 形状一律来自 [AppRadii]，用形状对比（Stadium / Squircel）建立层级；
/// 3. 主要按钮与指示器必须是全圆胶囊，卡片必须是 Squircel 高曲率圆角。
abstract final class AppTheme {
  static ThemeData build(AppColorTokens tokens) {
    final base = tokens.isDark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true);
    final colorScheme = ColorScheme(
      brightness: tokens.isDark ? Brightness.dark : Brightness.light,
      primary: tokens.primary,
      onPrimary: tokens.onPrimary,
      primaryContainer: tokens.primaryContainer,
      onPrimaryContainer: tokens.onPrimaryContainer,
      secondary: tokens.secondary,
      onSecondary: tokens.onSecondary,
      secondaryContainer: tokens.secondaryContainer,
      onSecondaryContainer: tokens.onSecondaryContainer,
      tertiary: tokens.tertiary,
      onTertiary: tokens.onTertiary,
      surface: tokens.surface,
      onSurface: tokens.onSurface,
      surfaceContainer: tokens.surfaceContainer,
      surfaceContainerHighest: tokens.surfaceContainerHighest,
      onSurfaceVariant: tokens.onSurfaceVariant,
      outline: tokens.outline,
      outlineVariant: tokens.outlineVariant,
      error: tokens.danger,
      onError: tokens.isDark ? const Color(0xFF3A0A0A) : Colors.white,
    );

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: tokens.scaffoldBackground,
      splashFactory: InkSparkle.splashFactory,
      // M3E 排版：编辑级层级，标题收紧字距、正文放宽行高
      textTheme: _buildTextTheme(base.textTheme, tokens),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: tokens.onSurface,
        titleTextStyle: TextStyle(
          color: tokens.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
        systemOverlayStyle: tokens.isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: tokens.surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.squircelAll),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.dialogAll),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: tokens.surface,
        modalBackgroundColor: tokens.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: tokens.outline,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.sheetTop),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: AppRadii.tileAll),
        iconColor: tokens.onSurfaceVariant,
        textColor: tokens.onSurface,
        minVerticalPadding: AppConstants.spaceS,
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        backgroundColor: tokens.surfaceContainerHigh,
        selectedColor: tokens.secondaryContainer,
        disabledColor: tokens.surfaceContainerLowest,
        labelStyle: TextStyle(
          color: tokens.onSurface,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        secondaryLabelStyle: TextStyle(color: tokens.onSecondaryContainer),
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spaceM,
          vertical: AppConstants.spaceXs,
        ),
        side: BorderSide.none,
        showCheckmark: false,
      ),
      // M3E：主要按钮必须是全圆胶囊
      //
      // ⚠️ `minimumSize` 用的是 `Size.fromHeight(52)`，宽度是 **infinity**
      // （表单里的按钮要撑满一行）。这带来一个坑：**把 FilledButton 直接放进
      // Row 里（尤其是和 `Spacer` 并排）会崩** —— Row 给非 flex 子节点的宽度
      // 约束是无界的，无限最小宽度直接触发
      // "BoxConstraints forces an infinite width"。
      // 需要"按内容自适应、贴边的按钮"时，请就地覆盖：
      // `style: FilledButton.styleFrom(minimumSize: const Size(0, 48))`。
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: tokens.primary,
          foregroundColor: tokens.onPrimary,
          disabledBackgroundColor: tokens.surfaceContainerHighest,
          disabledForegroundColor: tokens.onSurfaceVariant,
          elevation: 0,
          shape: const StadiumBorder(),
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: tokens.surfaceContainerLowest,
          foregroundColor: tokens.primary,
          elevation: 0,
          shape: const StadiumBorder(),
          minimumSize: const Size.fromHeight(52),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: tokens.primary,
          elevation: 0,
          shape: const StadiumBorder(),
          side: BorderSide(color: tokens.outline),
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: tokens.primary,
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: tokens.onSurfaceVariant,
          shape: RoundedRectangleBorder(borderRadius: AppRadii.innerAll),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.surfaceContainerHigh.withValues(alpha: 0.6),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spaceL,
          vertical: AppConstants.spaceL,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadii.tileAll,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.tileAll,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.tileAll,
          borderSide: BorderSide(color: tokens.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadii.tileAll,
          borderSide: BorderSide(color: tokens.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadii.tileAll,
          borderSide: BorderSide(color: tokens.danger, width: 2),
        ),
        labelStyle: TextStyle(color: tokens.onSurfaceVariant),
        hintStyle: TextStyle(
          color: tokens.onSurfaceVariant.withValues(alpha: 0.7),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: tokens.isDark
            ? tokens.surfaceContainerHighest
            : const Color(0xFF1F2A29),
        contentTextStyle: const TextStyle(color: Colors.white),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.innerAll),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 72,
        backgroundColor: tokens.surface,
        surfaceTintColor: Colors.transparent,
        // M3E：激活指示器必须是胶囊（Pill）
        indicatorShape: const StadiumBorder(),
        indicatorColor: tokens.secondaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
            letterSpacing: 0.1,
            color: selected ? tokens.onSecondaryContainer : tokens.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected ? tokens.onSecondaryContainer : tokens.onSurfaceVariant,
          );
        }),
      ),
      dividerTheme: DividerThemeData(
        color: tokens.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: tokens.onSecondaryContainer,
        unselectedLabelColor: tokens.onSurfaceVariant,
        // M3E：Tab 指示器也是胶囊
        indicator: BoxDecoration(
          color: tokens.secondaryContainer,
          borderRadius: AppRadii.stadiumAll,
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
        splashFactory: InkSparkle.splashFactory,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: tokens.primary,
        linearTrackColor: tokens.surfaceContainerHighest,
        linearMinHeight: 8,
        circularTrackColor: tokens.surfaceContainerHighest,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? tokens.onPrimary
                : tokens.outline),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? tokens.primary
                : tokens.surfaceContainerHighest),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: tokens.primary,
        inactiveTrackColor: tokens.surfaceContainerHighest,
        thumbColor: tokens.primary,
        overlayColor: tokens.primary.withValues(alpha: 0.12),
        trackHeight: 6,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: tokens.surfaceContainer,
          selectedBackgroundColor: tokens.secondaryContainer,
          selectedForegroundColor: tokens.onSecondaryContainer,
          foregroundColor: tokens.onSurfaceVariant,
          shape: const StadiumBorder(),
          side: BorderSide.none,
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: tokens.primaryContainer,
        foregroundColor: tokens.onPrimaryContainer,
        elevation: 0,
        // M3E 的大圆角 FAB
        shape: RoundedRectangleBorder(borderRadius: AppRadii.innerAll),
        extendedTextStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: tokens.onSurface.withValues(alpha: 0.92),
          borderRadius: AppRadii.smallAll,
        ),
        textStyle: TextStyle(color: tokens.surface, fontSize: 12),
      ),
    );
  }

  /// 编辑级排版层级：标题收紧字距（-0.5 ~ -0.2），正文放宽行高（1.5）。
  static TextTheme _buildTextTheme(TextTheme base, AppColorTokens tokens) {
    return base.copyWith(
      displaySmall: base.displaySmall?.copyWith(
        fontSize: 34,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        color: tokens.onSurface,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
        color: tokens.onSurface,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: tokens.onSurface,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: tokens.onSurface,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.1,
        color: tokens.onSurface,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: tokens.onSurface,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        fontSize: 15.5,
        height: 1.5,
        color: tokens.onSurface,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        fontSize: 14,
        height: 1.5,
        color: tokens.onSurface,
      ),
      bodySmall: base.bodySmall?.copyWith(
        fontSize: 12.5,
        height: 1.45,
        color: tokens.onSurfaceVariant,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
        color: tokens.onSurface,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: tokens.onSurfaceVariant,
      ),
      labelSmall: base.labelSmall?.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: tokens.onSurfaceVariant,
      ),
    );
  }
}
