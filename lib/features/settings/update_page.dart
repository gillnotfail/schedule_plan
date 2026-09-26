import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/core/theme/app_motion.dart';
import 'package:schedule_plan/core/widgets/app_card.dart';
import 'package:schedule_plan/core/widgets/app_snackbar.dart';
import 'package:schedule_plan/core/widgets/confirm_dialog.dart';
import 'package:schedule_plan/data/models/app_release.dart';
import 'package:schedule_plan/data/services/apk_installer.dart';
import 'package:schedule_plan/data/services/update_service.dart';

/// 检查与安装新版本的页面。
///
/// 把"整条升级链路现在走到哪一步"完整摊开给用户看：
/// 有没有新版、这次下载多少、正在下还是正在合成、什么时候要交给系统。
/// 分差升级的价值全在"少下载"上，所以**必须把省下的量说出来**，
/// 否则用户根本感知不到这条链路做了什么事。
///
/// 关于安装权限：Android 8 起必须有「安装未知应用」授权。
/// 这里在真的要装之前就提示并给出跳转入口，而不是等用户点了安装才失败——
/// 那种失败最容易被理解成"这个 App 有 bug"。
class UpdatePage extends StatefulWidget {
  const UpdatePage({super.key});

  @override
  State<UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends State<UpdatePage> with WidgetsBindingObserver {
  /// 上次提交安装时的目标版本。回到前台后拿它和真实版本比对，
  /// 用来判断"刚才那次安装到底成没成"——
  /// 系统装完会把进程杀掉重启，所以结果回调并不总是能送达。
  int? _installingTargetCode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 进页面就查一次，用户点进来显然是想知道有没有新版。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final service = context.read<UpdateService>();
      if (service.state.phase == UpdatePhase.idle) {
        service.check(force: true);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }
    // 从系统安装器回来：如果版本已经追平（甚至超过）刚才要装的版本，
    // 说明装成功了，直接把状态摆正，不必再麻烦用户重新检查一遍。
    final target = _installingTargetCode;
    if (target == null) {
      return;
    }
    _installingTargetCode = null;
    final service = context.read<UpdateService>();
    AppVersionSnapshot.fromPlatform().then((version) {
      if (!mounted) {
        return;
      }
      if (version.isKnown && version.versionCode >= target) {
        service.markInstalledExternally();
      } else {
        service.resetAfterInstallAttempt();
      }
    }).catchError((Object error, StackTrace stack) {
      AppLogger.e('回到前台后核对版本失败', error: error, stack: stack);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final service = context.watch<UpdateService>();
    final state = service.state;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.updateTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spaceL,
          AppConstants.spaceL,
          AppConstants.spaceL,
          AppConstants.spaceXl * 2,
        ),
        children: <Widget>[
          _CurrentVersionCard(state: state),
          const SizedBox(height: AppConstants.spaceL),
          if (!state.installAllowed && supportsInAppUpdate)
            _InstallPermissionNotice(
              onGrant: () => service.openInstallPermissionSettings(),
              onRecheck: () => service.check(force: true),
            ),
          _StatusBlock(service: service, state: state, onInstall: _startInstall),
          const SizedBox(height: AppConstants.spaceL),
          _MirrorSection(service: service),
        ],
      ),
    );
  }

  /// 提交安装前先把目标版本记下来。
  ///
  /// 系统装完会重启进程，Dart 侧的回调不一定送得到；回到前台时
  /// 用"实际版本是否已达到这个目标"来判断结果，比等回调可靠。
  Future<void> _startInstall() async {
    final target = context.read<UpdateService>().state.plan?.latest.versionCode;
    setState(() => _installingTargetCode = target);
    await context.read<UpdateService>().install();
  }
}

/// 当前版本与设备架构。
class _CurrentVersionCard extends StatelessWidget {
  const _CurrentVersionCard({required this.state});

  final UpdateState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final version = state.currentVersion;
    final abi = UpdateService.currentAbiName();

    return AppCard(
      child: Row(
        children: <Widget>[
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: AppRadii.innerAll,
            ),
            child: Icon(
              Icons.system_update_alt_rounded,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: AppConstants.spaceM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l10n.updateCurrentVersionLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  version.isKnown
                      ? l10n.updateVersionWithBuild(
                          version.versionName,
                          version.versionCode,
                        )
                      : l10n.updateVersionUnknown,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (abi.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    abi,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 「安装未知应用」未授权时的提示。
class _InstallPermissionNotice extends StatelessWidget {
  const _InstallPermissionNotice({
    required this.onGrant,
    required this.onRecheck,
  });

  final VoidCallback onGrant;
  final VoidCallback onRecheck;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spaceL),
      child: AppCard(
        color: theme.colorScheme.tertiaryContainer,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.verified_user_outlined,
                  size: 20,
                  color: theme.colorScheme.onTertiaryContainer,
                ),
                const SizedBox(width: AppConstants.spaceS),
                Expanded(
                  child: Text(
                    l10n.updateInstallBlockedTitle,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onTertiaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spaceS),
            Text(
              l10n.updateInstallBlockedDesc,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ),
            const SizedBox(height: AppConstants.spaceM),
            Row(
              children: <Widget>[
                FilledButton(
                  // Row 里的按钮默认会被拉到最大宽度，就地覆盖成贴合内容。
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44),
                  ),
                  onPressed: onGrant,
                  child: Text(l10n.updateGrantInstall),
                ),
                const SizedBox(width: AppConstants.spaceS),
                TextButton(
                  onPressed: onRecheck,
                  child: Text(l10n.updateRecheck),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 状态区：按当前阶段渲染不同的主体。
class _StatusBlock extends StatelessWidget {
  const _StatusBlock({
    required this.service,
    required this.state,
    required this.onInstall,
  });

  final UpdateService service;
  final UpdateState state;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    switch (state.phase) {
      case UpdatePhase.unsupported:
        return _SimpleHint(
          icon: Icons.info_outline_rounded,
          text: context.l10n.updateUnsupported,
        );
      case UpdatePhase.checking:
        return _ProgressCard(
          title: context.l10n.updateChecking,
          progress: null,
          onCancel: null,
        );
      case UpdatePhase.downloading:
        return _ProgressCard(
          title: context.l10n.updateDownloadingPercent(
            (state.progress * 100).round(),
          ),
          subtitle: state.fellBackToFull
              ? context.l10n.updateFellBackToFull
              : null,
          progress: state.progress,
          onCancel: service.cancel,
        );
      case UpdatePhase.assembling:
        return _ProgressCard(
          title: context.l10n.updateAssembling,
          subtitle: context.l10n.updateAssemblingHint,
          progress: null,
          onCancel: service.cancel,
        );
      case UpdatePhase.installing:
        return _SimpleHint(
          icon: Icons.hourglass_top_rounded,
          text: context.l10n.updateInstallingHint,
        );
      case UpdatePhase.installed:
        return _SimpleHint(
          icon: Icons.check_circle_outline_rounded,
          text: context.l10n.updateInstalledHint,
          tone: _HintTone.success,
        );
      case UpdatePhase.failed:
        return _FailureCard(service: service, state: state);
      case UpdatePhase.ready:
        return _ReadyCard(state: state, onInstall: onInstall);
      case UpdatePhase.available:
        return _AvailableCard(service: service, state: state);
      case UpdatePhase.upToDate:
      case UpdatePhase.idle:
        return _SimpleHint(
          icon: Icons.check_circle_outline_rounded,
          text: context.l10n.updateUpToDate,
          tone: _HintTone.success,
          action: TextButton(
            onPressed: () => service.check(force: true),
            child: Text(context.l10n.updateCheckAgain),
          ),
        );
    }
  }
}

enum _HintTone { neutral, success }

class _SimpleHint extends StatelessWidget {
  const _SimpleHint({
    required this.icon,
    required this.text,
    this.tone = _HintTone.neutral,
    this.action,
  });

  final IconData icon;
  final String text;
  final _HintTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = tone == _HintTone.success
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return AppCard(
      child: Row(
        children: <Widget>[
          Icon(icon, color: color),
          const SizedBox(width: AppConstants.spaceM),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
          if (action != null) ?action,
        ],
      ),
    );
  }
}

/// 下载 / 合成的进度卡。
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.title,
    required this.progress,
    required this.onCancel,
    this.subtitle,
  });

  final String title;
  final String? subtitle;

  /// `null` 表示不确定进度（检查中、合成中），交给系统画循环动画。
  final double? progress;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (subtitle != null) ...<Widget>[
            const SizedBox(height: AppConstants.spaceXs),
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: AppConstants.spaceM),
          ClipRRect(
            borderRadius: AppRadii.smallAll,
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              color: theme.colorScheme.primary,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
          if (onCancel != null) ...<Widget>[
            const SizedBox(height: AppConstants.spaceM),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onCancel,
                child: Text(l10n.cancel),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 有新版本可装。
class _AvailableCard extends StatelessWidget {
  const _AvailableCard({required this.service, required this.state});

  final UpdateService service;
  final UpdateState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final plan = state.plan!;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.new_releases_outlined,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: AppConstants.spaceS),
              Expanded(
                child: Text(
                  l10n.updateAvailableTitle(plan.latest.versionName),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceM),
          _SizeCompare(plan: plan),
          if (state.fellBackToFull) ...<Widget>[
            const SizedBox(height: AppConstants.spaceS),
            Text(
              l10n.updateFellBackToFull,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: AppConstants.spaceL),
          _Changelog(releases: plan.changelog),
          const SizedBox(height: AppConstants.spaceL),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                  ),
                  onPressed: () => service.prepare(),
                  icon: Icon(
                    plan.usesDelta
                        ? Icons.bolt_rounded
                        : Icons.download_rounded,
                  ),
                  label: Text(
                    plan.usesDelta
                        ? l10n.updateDownloadDelta
                        : l10n.updateDownloadFull,
                  ),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _confirmSkip(context, service, plan),
              child: Text(l10n.updateSkipVersion),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSkip(
    BuildContext context,
    UpdateService service,
    UpdatePlan plan,
  ) async {
    final l10n = context.l10n;
    final confirmed = await showAppConfirm(
      context: context,
      title: l10n.updateSkipVersion,
      body: l10n.updateSkipConfirmBody(plan.latest.versionName),
      confirmLabel: l10n.updateSkipVersion,
    );
    if (!confirmed) {
      return;
    }
    await service.skipCurrentPlan();
    if (context.mounted) {
      showAppSnackBar(context, l10n.updateSkippedHint);
    }
  }
}

/// 分差 vs 整包的下载量对比。这是分差升级唯一的"卖点"，
/// 所以放在最显眼的位置，用一句人话把省下的量说清楚。
class _SizeCompare extends StatelessWidget {
  const _SizeCompare({required this.plan});

  final UpdatePlan plan;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final download = formatBytes(plan.downloadBytes);
    final full = formatBytes(plan.fullBytes);

    return Container(
      padding: const EdgeInsets.all(AppConstants.spaceM),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: AppRadii.innerAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (plan.usesDelta)
                _Badge(
                  text: l10n.updateDeltaBadge,
                  color: theme.colorScheme.primary,
                )
              else
                _Badge(
                  text: l10n.updateFullBadge,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              const SizedBox(width: AppConstants.spaceS),
              Text(
                plan.usesDelta
                    ? l10n.updateSizeWithDelta(download, full)
                    : l10n.updateSizeFull(full),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (plan.usesDelta) ...<Widget>[
            const SizedBox(height: AppConstants.spaceS),
            Text(
              l10n.updateSavedHint(
                formatBytes(plan.fullBytes - plan.downloadBytes),
                (plan.savedRatio * 100).round(),
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: AppRadii.smallAll,
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

/// 更新内容：把"从当前版本到最新"之间的每一版都列出来。
///
/// 只看最新一版的说明是不够的——用户装的是 1.0.0 而最新是 1.0.3 时，
/// 中间两版改了什么他也需要知道。
class _Changelog extends StatelessWidget {
  const _Changelog({required this.releases});

  final List<AppRelease> releases;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l10n.updateChangesTitle,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppConstants.spaceS),
        for (final release in releases) ...<Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: AppConstants.spaceS),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      release.versionName,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (release.notes.isEmpty)
                      Text(
                        l10n.updateNoChanges,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    else
                      for (final note in release.notes)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            '· $note',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                  ],
                ),
              ),
            ],
          ),
          if (release != releases.last)
            const SizedBox(height: AppConstants.spaceM),
        ],
      ],
    );
  }
}

/// 新包已就绪，等着交给系统。
class _ReadyCard extends StatelessWidget {
  const _ReadyCard({required this.state, required this.onInstall});

  final UpdateState state;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary),
              const SizedBox(width: AppConstants.spaceS),
              Expanded(
                child: Text(
                  l10n.updateReadyTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceS),
          Text(
            state.usedDelta
                ? l10n.updateReadyDeltaHint
                : l10n.updateReadyFullHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppConstants.spaceM),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: onInstall,
            icon: const Icon(Icons.install_mobile_rounded),
            label: Text(l10n.updateInstallNow),
          ),
        ],
      ),
    );
  }
}

class _FailureCard extends StatelessWidget {
  const _FailureCard({required this.service, required this.state});

  final UpdateService service;
  final UpdateState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return AppCard(
      color: theme.colorScheme.errorContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.error_outline_rounded,
                color: theme.colorScheme.onErrorContainer,
              ),
              const SizedBox(width: AppConstants.spaceS),
              Expanded(
                child: Text(
                  _messageOf(context, state.failure),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (state.failureDetail != null) ...<Widget>[
            const SizedBox(height: AppConstants.spaceXs),
            // 底层报错只作参考，样式上刻意弱化：用户关心的是"接下来干什么"。
            Text(
              state.failureDetail!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer.withValues(
                  alpha: 0.75,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppConstants.spaceM),
          Row(
            children: <Widget>[
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: () => _retry(context),
                child: Text(l10n.updateRetry),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 有已下好的包就重试安装，否则重试下载；再不行才回头重新检查。
  void _retry(BuildContext context) {
    if (state.failure == UpdateFailure.installBlocked) {
      service.openInstallPermissionSettings();
      return;
    }
    if (state.preparedApkPath != null) {
      service.resetAfterInstallAttempt();
      service.install();
      return;
    }
    if (state.plan != null) {
      service.prepare();
      return;
    }
    service.check(force: true);
  }

  String _messageOf(BuildContext context, UpdateFailure? failure) {
    final l10n = context.l10n;
    return switch (failure) {
      UpdateFailure.network => l10n.updateFailureNetwork,
      UpdateFailure.manifest => l10n.updateFailureManifest,
      UpdateFailure.assetMissing => l10n.updateFailureAssetMissing,
      UpdateFailure.hashMismatch => l10n.updateFailureHash,
      UpdateFailure.deltaMismatch => l10n.updateFailureDelta,
      UpdateFailure.noSpace => l10n.updateFailureNoSpace,
      UpdateFailure.installBlocked => l10n.updateFailureInstallBlocked,
      UpdateFailure.installRejected => l10n.updateFailureInstallRejected,
      _ => l10n.updateFailureUnknown,
    };
  }
}

/// 下载加速地址设置。
///
/// 默认折叠、默认空：不替用户做选择。GitHub 附件在部分网络下确实很慢，
/// 但"填哪个代理"这件事应该由用户自己决定，而不是我们塞一个默认值进去。
class _MirrorSection extends StatefulWidget {
  const _MirrorSection({required this.service});

  final UpdateService service;

  @override
  State<_MirrorSection> createState() => _MirrorSectionState();
}

class _MirrorSectionState extends State<_MirrorSection> {
  bool _expanded = false;
  late final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.service.mirrorPrefixes().then((prefixes) {
      if (!mounted) {
        return;
      }
      setState(() => _controller.text = prefixes.join('\n'));
    }).catchError((Object error, StackTrace stack) {
      AppLogger.e('读取下载加速地址失败', error: error, stack: stack);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            borderRadius: AppRadii.innerAll,
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.cloud_sync_outlined,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppConstants.spaceM),
                  Expanded(
                    child: Text(
                      l10n.updateMirrorTitle,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: AppMotion.quick,
                    curve: AppMotion.effects,
                    child: const Icon(Icons.expand_more_rounded),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: AppMotion.quick,
            sizeCurve: AppMotion.effects,
            crossFadeState: _expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.only(top: AppConstants.spaceM),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    l10n.updateMirrorDesc,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppConstants.spaceM),
                  TextField(
                    controller: _controller,
                    maxLines: 3,
                    minLines: 2,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      hintText: l10n.updateMirrorHint,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: AppConstants.spaceM),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44),
                      ),
                      onPressed: () async {
                        final prefixes = _controller.text
                            .split(RegExp(r'[\r\n,]+'))
                            .map((line) => line.trim())
                            .where((line) => line.isNotEmpty)
                            .toList();
                        await widget.service.saveMirrorPrefixes(prefixes);
                        if (context.mounted) {
                          showAppSnackBar(context, l10n.updateMirrorSaved);
                        }
                      },
                      child: Text(l10n.save),
                    ),
                  ),
                ],
              ),
            ),
            secondChild: const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
