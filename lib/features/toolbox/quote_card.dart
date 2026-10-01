import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/theme/app_motion.dart';
import 'package:schedule_plan/core/widgets/app_snackbar.dart';
import 'package:schedule_plan/core/widgets/squishy_tap.dart';
import 'package:schedule_plan/data/models/quote.dart';
import 'package:schedule_plan/data/services/quote_service.dart';

/// 工具箱首屏下方的「每日一句」大卡片（用户规格第 21 轮）。
///
/// 用户规格：
/// > "下面确实有点空，但是不用担心，有一张大卡片放在下面，饱和度第一点，
/// >  可以加一点诗、歌词、语录等，每次点击这个区域或者切换到这一页，
/// >  就随机跳出来。……颜色和卡片的搭配适应整个屏幕。"
///
/// 三条设计口径：
/// 1. **低饱和 + 居中**：底色不是某个固定的"文艺色"，而是
///    `surface ← primary/tertiary` 按 7%~20% 互溶出来的**淡淡一层染**——
///    六套主题换哪个都自动对上，暗色主题自动变成"深底微光"，不会有一块
///    跳出来的亮色卡；正文仍用 `onSurface`，对比度不被牺牲。
///    排版**整条竖列居中**（引号封面 → 正文 → 出处 → 轻触提示），
///    用户规格第 21 轮："字体居中吧，轻松一点，不要太刻板"。
/// 2. **换句时机**：点卡片换一句（[SquishyTap] 的按压回弹 + 轻触觉）；
///    从别的 Tab 切回来、从第 2 页滑回来由外部改 [rerollToken] 触发换句。
///    换句用淡入 + 6% 上移，是"颜色/透明度"为主的过渡，所以走
///    [AppMotion.effects] 这条单调曲线，不用过冲曲线。
/// 3. **不空壳**：语料读不到时整块卡片隐藏；正在读时给一张同高的骨架卡，
///    避免首帧塌一下又弹出来。
class QuoteCard extends StatefulWidget {
  const QuoteCard({super.key, this.rerollToken = 0, this.service});

  /// 外部"换一句"的信号：值一变就重新抽。
  ///
  /// 用自增的整数而不是回调，是因为触发点在父级的 `onPageChanged` /
  /// 导航监听里，那里只方便改状态，不方便去 `GlobalKey` 上喊话。
  final int rerollToken;

  /// 语料服务（默认用全局共用的那一份；测试可注入替身）。
  final QuoteService? service;

  @override
  State<QuoteCard> createState() => _QuoteCardState();
}

class _QuoteCardState extends State<QuoteCard> {
  late final QuoteService _service = widget.service ?? QuoteService.shared;

  Quote? _quote;
  bool _loading = true;

  /// 抽句的世代号：连续点两下时，只认最后一次的结果，避免旧结果后到覆盖新结果。
  int _rollToken = 0;

  @override
  void initState() {
    super.initState();
    _roll();
  }

  @override
  void didUpdateWidget(covariant QuoteCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.rerollToken != oldWidget.rerollToken) {
      _roll();
    }
  }

  Future<void> _roll() async {
    final token = ++_rollToken;
    final quote = await _service.next();
    if (!mounted || token != _rollToken) {
      return;
    }
    setState(() {
      _quote = quote;
      _loading = false;
    });
  }

  /// 长按 → 说明语料从哪来、想加句子该往哪放。
  ///
  /// 这一条不是装饰：语料是**用户可自己扩写**的 JSON，不给出口的话
  /// "我自己后续可以往里面加"就只能靠翻代码。
  Future<void> _showSources() async {
    AppMotion.select();
    final l10n = context.l10n;
    final path = _service.userFilePath;
    final copied = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final scheme = theme.colorScheme;
        return AlertDialog(
          title: Text(l10n.quoteCardSourceTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                l10n.quoteCardSourceBuiltIn(_service.builtInCount),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: AppConstants.spaceS),
              Text(
                path == null
                    ? l10n.quoteCardSourceCustomMissing('…')
                    : _service.hasUserFile
                    ? l10n.quoteCardSourceCustom(path)
                    : l10n.quoteCardSourceCustomMissing(path),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppConstants.spaceM),
              Text(
                l10n.quoteCardSourceFormat,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton.tonal(
              onPressed: path == null
                  ? null
                  : () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.copyAction),
            ),
          ],
        );
      },
    );
    if (copied != true || path == null || !mounted) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: path));
    if (!mounted) {
      return;
    }
    showAppSnackBar(context, l10n.copyDone);
  }

  @override
  Widget build(BuildContext context) {
    final quote = _quote;
    if (quote == null) {
      return _loading
          ? const _QuoteSkeleton()
          : const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final radius = BorderRadius.circular(AppRadii.squircel);
    // 染色的两端都往 surface 兑：浅色主题得到"米白里透一点主色"，
    // 暗色主题得到"深底上泛一点微光"，同一条公式适配六套主题。
    final tintStart = Color.lerp(
      scheme.surface,
      scheme.primary,
      isDark ? 0.20 : 0.10,
    )!;
    final tintEnd = Color.lerp(
      scheme.surface,
      scheme.tertiary,
      isDark ? 0.16 : 0.07,
    )!;
    return SquishyTap(
      onTap: _roll,
      onLongPress: _showSources,
      pressedScale: 0.985,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: scheme.shadow.withValues(alpha: isDark ? 0.34 : 0.07),
              blurRadius: 18,
              offset: const Offset(0, 6),
              spreadRadius: -4,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[tintStart, tintEnd],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.spaceL,
                AppConstants.spaceL,
                AppConstants.spaceL,
                AppConstants.spaceM,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // 一枚引号当"封面"：居中摆，整块内容就成了一条对称的竖列，
                  // 读起来松，不像表单那样一格一格顶着左边。
                  Icon(
                    Icons.format_quote_rounded,
                    size: 28,
                    color: scheme.primary.withValues(alpha: 0.42),
                  ),
                  const SizedBox(height: AppConstants.spaceS),
                  AnimatedSize(
                    duration: AppMotion.standard,
                    curve: AppMotion.effects,
                    alignment: Alignment.topCenter,
                    child: AnimatedSwitcher(
                      duration: AppMotion.standard,
                      switchInCurve: AppMotion.effects,
                      switchOutCurve: AppMotion.effects,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.06),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: AppMotion.effects,
                            ),
                          ),
                          child: child,
                        ),
                      ),
                      child: _QuoteBody(key: ValueKey(quote.text), quote: quote),
                    ),
                  ),
                  const SizedBox(height: AppConstants.spaceS),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(
                        Icons.refresh_rounded,
                        size: 13,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
                      ),
                      const SizedBox(width: AppConstants.spaceXs),
                      Text(
                        context.l10n.quoteCardTapHint,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 正文 + 出处：换句时整块淡出淡入（[AnimatedSwitcher] 的 key 落在正文上）。
///
/// 两行都是**居中**的（用户规格第 21 轮："字体居中吧，轻松一点，不要太刻板"）：
/// 左边靠齐会读成一张信息卡，居中才像一页书。
class _QuoteBody extends StatelessWidget {
  const _QuoteBody({super.key, required this.quote});

  final Quote quote;

  /// 正文块的最小高度。
  ///
  /// 内置语料绝大多数落在一到两行，钉住一个"两行半"的高度之后
  /// **换句时卡片高度基本不动**（只有个别长句会再长一点点，外面套了
  /// AnimatedSize 兜住），同时也让这张卡比上面的工具卡**明显高一档**，
  /// 撑得起"大卡片"这个定位。
  static const double _minLinesHeight = 84;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _minLinesHeight),
          // 垂直居中：一行的句子上下各留一点，不会整块贴着顶上的引号，
          // 把出处推到很远的地方
          child: Align(
            alignment: Alignment.center,
            child: Text(
              quote.text,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 17,
                height: 1.7,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ),
        if (quote.hasFrom) ...<Widget>[
          const SizedBox(height: AppConstants.spaceS),
          Text(
            '—— ${quote.from}',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// 正在读语料时的骨架：高度与真实卡片一致，避免首帧塌一下又弹回来。
///
/// 192 = 上下内边距 28 + 引号 28 + 两处间隔 16 + 正文块 84（含出处 24）+ 提示行 15。
/// 真卡片的正文比两行长时会再高一点，这里取"最常见那一档"即可。
class _QuoteSkeleton extends StatelessWidget {
  const _QuoteSkeleton();

  static const double _height = 192;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bar = scheme.onSurface.withValues(alpha: 0.08);
    return Container(
      height: _height,
      padding: const EdgeInsets.all(AppConstants.spaceL),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadii.squircel),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 28,
            height: 24,
            decoration: BoxDecoration(color: bar, borderRadius: AppRadii.smallAll),
          ),
          const SizedBox(height: AppConstants.spaceM),
          _SkeletonBar(width: 200, color: bar),
          const SizedBox(height: AppConstants.spaceS),
          _SkeletonBar(width: 140, color: bar),
          const SizedBox(height: AppConstants.spaceM),
          _SkeletonBar(width: 96, height: 10, color: bar),
        ],
      ),
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({
    required this.width,
    required this.color,
    this.height = 14,
  });

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: color, borderRadius: AppRadii.stadiumAll),
    );
  }
}
