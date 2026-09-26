import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/constants/setting_keys.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/theme/app_motion.dart';
import 'package:schedule_plan/core/widgets/app_card.dart';
import 'package:schedule_plan/core/widgets/settings_tile.dart';
import 'package:schedule_plan/data/repositories/settings_repository.dart';
import 'package:schedule_plan/data/settings_state.dart';

/// 统计设置（用户规格：统计相关配置从系统设置里搬出来，独立成页）。
///
/// 只放「影响统计口径与判定结果」的参数，App 级的显示/权限不在这里。
class StatisticsSettingsPage extends StatelessWidget {
  const StatisticsSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settings = context.watch<SettingsState>();
    final repo = context.read<SettingsRepository>();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.statisticsSettings)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppConstants.spaceXl),
        children: <Widget>[
          GroupHeader(
            title: l10n.riskThreshold,
            icon: Icons.warning_amber_rounded,
            description: l10n.statsRiskThresholdDesc,
          ),
          SettingsGroup(
            dividerIndent: AppConstants.spaceXl,
            children: <Widget>[
              _ThresholdSlider(
                label: l10n.riskThreshold,
                value: settings.riskAbsenceThreshold,
                min: 1,
                max: 10,
                unit: l10n.unitTimes,
                onChanged: (value) => repo
                    .writeInt(SettingKeys.riskAbsenceThreshold, value)
                    .then((_) => settings.load()),
              ),
              _ThresholdSlider(
                label: '${l10n.riskThreshold} · ${l10n.statusAbsent}',
                value: settings.riskWeightAbsent,
                min: 1,
                max: 5,
                unit: l10n.unitTimes,
                onChanged: (value) => repo
                    .writeInt(SettingKeys.riskWeightAbsent, value)
                    .then((_) => settings.load()),
              ),
              _ThresholdSlider(
                label: '${l10n.riskThreshold} · ${l10n.statusLate}',
                value: settings.riskWeightLate,
                min: 1,
                max: 5,
                unit: l10n.unitTimes,
                onChanged: (value) => repo
                    .writeInt(SettingKeys.riskWeightLate, value)
                    .then((_) => settings.load()),
              ),
              _ThresholdSlider(
                label: '${l10n.riskThreshold} · ${l10n.statusEarlyLeave}',
                value: settings.riskWeightEarlyLeave,
                min: 1,
                max: 5,
                unit: l10n.unitTimes,
                onChanged: (value) => repo
                    .writeInt(SettingKeys.riskWeightEarlyLeave, value)
                    .then((_) => settings.load()),
              ),
            ],
          ),
          GroupHeader(
            title: l10n.attendanceWarnThreshold,
            icon: Icons.trending_down_rounded,
            description: l10n.statsWarnThresholdDesc,
          ),
          SettingsGroup(
            dividerIndent: AppConstants.spaceXl,
            children: <Widget>[
              _ThresholdSlider(
                label: l10n.attendanceWarnThreshold,
                value: settings.attendanceWarnRate.round(),
                min: 50,
                max: 100,
                unit: l10n.unitPercent,
                onChanged: (value) => repo
                    .writeDouble(
                      SettingKeys.attendanceWarnRate,
                      value.toDouble(),
                    )
                    .then((_) => settings.load()),
              ),
            ],
          ),
          GroupHeader(
            title: l10n.retentionDays,
            icon: Icons.cleaning_services_outlined,
          ),
          SettingsGroup(
            dividerIndent: AppConstants.spaceXl,
            children: <Widget>[
              _ThresholdSlider(
                label: l10n.retentionDays,
                value: settings.attendanceRetentionDays,
                min: 30,
                max: 720,
                unit: l10n.unitDays,
                onChanged: (value) => repo
                    .writeInt(SettingKeys.attendanceRetentionDays, value)
                    .then((_) => settings.load()),
              ),
              _ThresholdSlider(
                label: l10n.retentionImportLogDays,
                value: settings.importLogRetentionDays,
                min: 30,
                max: 1080,
                unit: l10n.unitDays,
                onChanged: (value) => repo
                    .writeInt(SettingKeys.importLogRetentionDays, value)
                    .then((_) => settings.load()),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.spaceL,
              AppConstants.spaceL,
              AppConstants.spaceL,
              0,
            ),
            child: AppCard(
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.lightbulb_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: AppConstants.spaceS),
                  Expanded(
                    child: Text(
                      l10n.statisticsSettingsDesc,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 阈值滑块：拖动即保存，右侧实时显示当前值。
class _ThresholdSlider extends StatelessWidget {
  const _ThresholdSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final String unit;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final safe = value.clamp(min, max);
    return Padding(
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
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              AnimatedContainer(
                duration: AppMotion.quick,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spaceM,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.75),
                  borderRadius: AppRadii.stadiumAll,
                ),
                child: Text(
                  '$safe$unit',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          Slider(
            value: safe.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: max - min,
            label: '$safe',
            onChanged: (next) => onChanged(next.round()),
          ),
        ],
      ),
    );
  }
}
