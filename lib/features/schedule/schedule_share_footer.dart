import 'package:flutter/material.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';

/// 课表分享卡片的**底部信息带**：左边 app 名，右边二维码占位。
///
/// 用户规格（第 8 轮）："自动截图当前课表的屏幕，同时在课表最下方加上 app 名。
/// 后续可能还要加上二维码供分享……你留个位置，做好标记，
/// 包括 app 和二维码位置，后续我自己加上。"
///
/// 所以这条信息带就是留给用户的**两个替换点**：
///
/// 1. **app 名** —— [`_appTitle`]，目前取 `l10n.appTitle`（全面课表计划）。
///    要换品牌名 / 加 slogan，只改这一行。
/// 2. **二维码** —— [`_QrPlaceholder`]，二维码还没定，先画一个虚线感的占位框。
///    定了以后**整个把 `_QrPlaceholder` 换成真实的二维码组件**（qr_flutter 之类），
///    占位尺寸 [`AppConstants.shareQrPlaceholderSize`] 就是给二维码留的位置，
///    宽高都按它来，别改小（否则印出来扫不动）。
///
/// 这条信息带平时**不在屏幕上**（被摆在屏幕外，见课表页 `_shareFooterKey`），
/// 只在截图时由 `ScheduleShare` 拼到课表图的最下方。
class ScheduleShareFooter extends StatelessWidget {
  const ScheduleShareFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      height: AppConstants.shareFooterHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceL),
      decoration: BoxDecoration(color: scheme.surface),
      child: Row(
        children: <Widget>[
          // ── 替换点 1：app 名 ────────────────────────────────────────────
          Expanded(
            child: Text(
              context.l10n.appTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(width: AppConstants.spaceM),
          // ── 替换点 2：二维码占位 ────────────────────────────────────────
          const _QrPlaceholder(),
        ],
      ),
    );
  }
}

/// 二维码占位：虚线感的方框 + 图标 + 文案，明确"这里是留给二维码的"。
class _QrPlaceholder extends StatelessWidget {
  const _QrPlaceholder();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final size = AppConstants.shareQrPlaceholderSize;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        // 占位示意：等确认二维码方案后，这个 Container 会被整个换掉
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: AppRadii.tileAll,
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.6),
          width: 1.2,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.qr_code_2_rounded,
              size: size * 0.42, color: scheme.onSurfaceVariant),
          const SizedBox(height: 2),
          Text(
            context.l10n.shareQrPlaceholder,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 9,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
