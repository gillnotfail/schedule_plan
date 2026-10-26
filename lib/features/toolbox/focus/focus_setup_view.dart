import 'package:flutter/material.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/widgets/app_card.dart';
import 'package:schedule_plan/features/toolbox/focus/focus_clock.dart';
import 'package:schedule_plan/features/toolbox/focus/focus_duration_wheel.dart';
import 'package:schedule_plan/features/toolbox/focus/focus_presets.dart';

/// 专注的准备态：挑时长、起个名字（选填），然后开始。
///
/// 分成"命名"和"时长"两张卡是刻意的：命名是**可选**的，时长是**必须**的，
/// 混在一张卡里会让人以为名字也得填。所以时长放在下面、离开始按钮更近。
class FocusSetupView extends StatelessWidget {
  const FocusSetupView({
    super.key,
    required this.total,
    required this.category,
    required this.label,
    required this.labelController,
    required this.soundEnabled,
    required this.strongLockEnabled,
    required this.onTotalChanged,
    required this.onCategoryChanged,
    required this.onLabelChanged,
    required this.onSoundChanged,
    required this.onStrongLockChanged,
    required this.onStart,
  });

  final Duration total;
  final FocusCategory? category;
  final String? label;

  /// 名字输入框的控制器由页面持有 —— 开始/重置之后页面要能清空它。
  final TextEditingController labelController;

  final bool soundEnabled;
  final bool strongLockEnabled;

  final ValueChanged<Duration> onTotalChanged;
  final ValueChanged<FocusCategory?> onCategoryChanged;
  final ValueChanged<String?> onLabelChanged;
  final ValueChanged<bool> onSoundChanged;
  final ValueChanged<bool> onStrongLockChanged;
  final VoidCallback onStart;

  /// 下限 1 分钟。**不替用户改数字**（硬掰会跟正在滑的手抢），
  /// 只把开始按钮按下去 —— 并把原因写在按钮上面。
  bool get _canStart => total.inSeconds >= AppConstants.focusMinSeconds;

  @override
  Widget build(BuildContext context) {
    // 用户规格：**准备态必须一页放得下，不要上下滑**。
    //
    // 为此砍掉了三样东西，都有明确的理由：
    // - 顶部那个预览环（原来 170px）：它里面的数字和下面滚轮**完全重复**，
    //   圆的视觉主场在专注态（那个环形倒计时），准备态不需要；
    // - 预设胶囊从四行平铺改**单行横滑**（11 个全在，只是不再往下叠）；
    // - 两个开关从上下两行并成**一排**。
    // ListView 只留作极端小屏（内容真超了）的兜底，正常机型不会滚。
    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.spaceL,
              AppConstants.spaceL,
              AppConstants.spaceL,
              AppConstants.spaceM,
            ),
            children: <Widget>[
              _nameCard(context),
              const SizedBox(height: AppConstants.spaceS),
              _durationCard(context),
              const SizedBox(height: AppConstants.spaceS),
              _optionsCard(context),
            ],
          ),
        ),
        _bottomBar(context),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 命名
  // ---------------------------------------------------------------------------

  Widget _nameCard(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceL,
        AppConstants.spaceM,
        AppConstants.spaceL,
        AppConstants.spaceM,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l10n.focusNameLabel,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                l10n.focusNameOptional,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceS),
          Wrap(
            spacing: AppConstants.spaceS,
            runSpacing: AppConstants.spaceS,
            children: FocusCategory.values
                .map((item) => _CategoryChip(
                      category: item,
                      selected: item == category,
                      onTap: () => onCategoryChanged(
                        item == category ? null : item,
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: AppConstants.spaceS),
          // 预设**单行横滑**，不换行。原来 11 个胶囊平铺要占四行、两百多像素，
          // 是"备注占满整页"的主因；横滑之后只占一行，全部预设仍然都在。
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Wrap(
              spacing: AppConstants.spaceS,
              children: _visiblePresets()
                  .map((preset) => _PresetChip(
                        label: focusPresetLabel(context, preset.id) ?? preset.id,
                        selected: preset.id == label,
                        onTap: () => _pickPreset(context, preset),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: AppConstants.spaceS),
          TextField(
            controller: labelController,
            textInputAction: TextInputAction.done,
            maxLength: 20,
            decoration: InputDecoration(
              hintText: l10n.focusNameHint,
              prefixIcon: const Icon(Icons.edit_outlined, size: 20),
              counterText: '',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spaceM,
                vertical: AppConstants.spaceM,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.tile),
              ),
            ),
            onChanged: onLabelChanged,
          ),
        ],
      ),
    );
  }

  /// 选了类别就只显示那一类的预设；没选就全列出来 ——
  /// 让"先选类别"永远不是必须的第一步。
  List<FocusPreset> _visiblePresets() {
    final selected = category;
    if (selected == null) {
      return focusPresets;
    }
    return presetsOf(selected);
  }

  void _pickPreset(BuildContext context, FocusPreset preset) {
    // 点预设时把名字回填到输入框，用户能接着改 —— 改了就变成自定义名字。
    // 注意：这里是**程序化**改 text，不会触发 TextField.onChanged，
    // 所以不会把刚存好的稳定 id 冲掉。
    labelController.text = focusPresetLabel(context, preset.id) ?? preset.id;
    onLabelChanged(preset.id);
    if (category == null) {
      onCategoryChanged(preset.category);
    }
  }

  // ---------------------------------------------------------------------------
  // 时长
  // ---------------------------------------------------------------------------

  Widget _durationCard(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceL,
        AppConstants.spaceM,
        AppConstants.spaceL,
        AppConstants.spaceM,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l10n.focusDurationTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                formatFocusSpoken(total),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          FocusDurationWheel(value: total, onChanged: onTotalChanged),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 选项
  // ---------------------------------------------------------------------------

  /// 两个开关**并成一排**：原来是上下两行、下面那行还带一句解释，
  /// 单这两行就吃掉一百多像素。「更强锁定」的说明改成开启后才出现 ——
  /// 没开的时候解释也用不上，开了才需要知道手机变成了什么样。
  Widget _optionsCard(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceM,
        AppConstants.spaceXs,
        AppConstants.spaceXs,
        AppConstants.spaceXs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _OptionTile(
                  icon: Icons.volume_up_outlined,
                  title: l10n.focusSoundToggle,
                  value: soundEnabled,
                  onChanged: onSoundChanged,
                ),
              ),
              Expanded(
                child: _OptionTile(
                  icon: Icons.lock_outline,
                  title: l10n.focusStrongLockToggle,
                  value: strongLockEnabled,
                  onChanged: onStrongLockChanged,
                ),
              ),
            ],
          ),
          if (strongLockEnabled)
            Padding(
              padding: const EdgeInsets.only(
                left: AppConstants.spaceXs,
                right: AppConstants.spaceM,
                bottom: AppConstants.spaceXs,
              ),
              child: Text(
                l10n.focusStrongLockDesc,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 底部：开始
  // ---------------------------------------------------------------------------

  Widget _bottomBar(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spaceL,
          AppConstants.spaceS,
          AppConstants.spaceL,
          AppConstants.spaceL,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (!_canStart)
              Padding(
                padding: const EdgeInsets.only(bottom: AppConstants.spaceS),
                child: Text(
                  l10n.focusMinDurationHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _canStart ? onStart : null,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(l10n.focusStartAction),
              ),
            ),
            const SizedBox(height: AppConstants.spaceS),
            Text(
              l10n.focusLockNotice,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 类别小胶囊。
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final FocusCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _ChipShell(
      selected: selected,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            category.icon,
            size: 16,
            color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppConstants.spaceXs),
          Text(
            focusCategoryLabel(context, category),
            style: theme.textTheme.labelLarge?.copyWith(
              color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// 预设名小胶囊。
class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _ChipShell(
      selected: selected,
      onTap: onTap,
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}

/// 两个胶囊共用的外壳（选中态走主题色，未选中是浅底描边）。
class _ChipShell extends StatelessWidget {
  const _ChipShell({
    required this.child,
    required this.selected,
    required this.onTap,
  });

  final Widget child;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primaryContainer
          : scheme.surfaceContainerHighest.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(AppRadii.stadium),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spaceM,
            vertical: AppConstants.spaceS,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 一个紧凑开关：图标 + 标题 + Switch，横排只占一行。
///
/// 这是从上下两行的 [_OptionRow]（已删）压下来的 —— 准备态要一屏装下，
/// 每个开关省下的 50 多像素都是必要的。
class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: AppConstants.spaceXs),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
