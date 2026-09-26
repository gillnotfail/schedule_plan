import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/core/theme/app_motion.dart';
import 'package:schedule_plan/core/widgets/app_card.dart';
import 'package:schedule_plan/core/widgets/app_snackbar.dart';
import 'package:schedule_plan/core/widgets/pulse_loading.dart';
import 'package:schedule_plan/core/widgets/staggered_entrance.dart';
import 'package:schedule_plan/data/repositories/class_repository.dart';
import 'package:schedule_plan/data/repositories/course_repository.dart';
import 'package:schedule_plan/data/repositories/lesson_repository.dart';
import 'package:schedule_plan/data/services/schedule_ocr_import_service.dart';
import 'package:schedule_plan/data/services/schedule_ocr_service.dart';
import 'package:schedule_plan/data/services/schedule_ocr_types.dart';
import 'package:schedule_plan/features/management/crop_selector.dart';
import 'package:schedule_plan/l10n/generated/app_localizations.dart';

/// 拍照 / 选图 → 本机识别 → 核对 → 导入课表（第 11 轮）。
///
/// ## 回答用户的核心疑问（这一页就是为了回答它）
///
/// 用户问："能否调用手机本身的计算能力或者功能，比方说 OCR 识图。
/// 用户拍照课表，自动识别，自动生成课表。不需要 ai 或者 llm 提供商？"
///
/// **可以，而且这一页就是照着"完全不依赖 AI / LLM 服务商"做的：**
///
/// | 环节 | 用什么 | 联网? |
/// |---|---|---|
/// | 拍照 / 选图 | 手机相机与相册（`image_picker`） | ❌ |
/// | 文字识别 | 手机本机 OCR（Android = Google ML Kit 离线模型；iOS = Apple Vision） | ❌ |
/// | 表格还原 | 本地几何规则（`ScheduleOcrParser`） | ❌ |
/// | 落库 | 本地 SQLite | ❌ |
///
/// 关键在于**课表是结构化表格**：字少、字大、表头规整（"周一…周五" / "第 N 节"）。
/// 这种场景下"文字识别 + 坐标聚类"就足以还原整张表，
/// 不需要语言模型去理解语义，也就没有 API Key、没有按次计费、没有隐私外传。
///
/// ## 机型适配（第 12 轮明确，见 [_DeviceSupportCard]）
///
/// 用户给的目标机型是"安卓最近三代、可带 Google 服务、但都用在国产手机上
/// （小米 / OPPO / vivo 等）"，并特别指出 **华为是鸿蒙系统、可能得额外标注**。
///
/// - **国产安卓**：正常可用。文字识别走设备自带的离线引擎，
///   有 Google 服务就用 ML Kit，没有也能回落到系统自带识别，全程不联网；
/// - **华为鸿蒙（HarmonyOS）**：**暂未适配**。鸿蒙既没有 GMS 的 ML Kit，
///   也没有 Apple Vision，需要在引擎层新增一个 HarmonyOS 实现（见
///   `ScheduleOcrService.setupRecognizer`），当前对这类设备明确提示走 Excel / 手动排课；
/// - **iOS**：能力已预留在 `VNRecognizeTextRequest`，等 iOS 版本一并启用。
///
/// 三档的结论都写在 [_DeviceSupportCard] 里，不靠老师自己猜。
///
/// ## 三个步骤
///
/// 1. **选图**（[_Stage.pick]）：拍照或从相册选，附拍摄建议；
/// 2. **框选**（[_Stage.crop]）：手机拍的照片多半带桌面、手指、标题，
///    框住表格能显著提高识别率（也是本页最"值钱"的一步）；
/// 3. **核对**（[_Stage.review]）：逐条显示识别结果，可改课程名、可删误识项，
///    确认后一次性导入。
///
/// 置信度低时页面顶部会挂一条明显提示，但不拦着老师继续——
/// 老师自己最清楚这张照片拍得好不好。
class CourseOcrPage extends StatefulWidget {
  const CourseOcrPage({super.key});

  @override
  State<CourseOcrPage> createState() => _CourseOcrPageState();
}

enum _Stage { pick, crop, review }

class _CourseOcrPageState extends State<CourseOcrPage> {
  _Stage _stage = _Stage.pick;

  Uint8List? _bytes;

  /// 框选区域（相对图片的比例，0~1）。
  Rect _crop = const Rect.fromLTRB(0.06, 0.08, 0.94, 0.92);

  ScheduleOcrResult? _result;
  bool _busy = false;
  String? _errorKey;

  final ImagePicker _picker = ImagePicker();

  // ---------------------------------------------------------------------------
  // 第 1 步：选图
  // ---------------------------------------------------------------------------

  Future<void> _pick(ImageSource source) async {
    setState(() => _errorKey = null);
    try {
      final file = await _picker.pickImage(
        source: source,
        // 长边压到 1600：手机原图 4000×3000 直接喂给识别引擎又慢又吃内存，
        // 而课表只要字看得清就够，这个尺寸不影响准确率。
        maxWidth: AppConstants.ocrMaxImageSide.toDouble(),
        maxHeight: AppConstants.ocrMaxImageSide.toDouble(),
        imageQuality: 92,
      );
      if (file == null) {
        return;
      }
      final bytes = await file.readAsBytes();
      if (!mounted) {
        return;
      }
      setState(() {
        _bytes = bytes;
        _crop = const Rect.fromLTRB(0.06, 0.08, 0.94, 0.92);
        _stage = _Stage.crop;
      });
    } catch (error, stack) {
      AppLogger.e('选择课表照片失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      setState(() => _errorKey = 'ocrNoPhotoPermission');
    }
  }

  // ---------------------------------------------------------------------------
  // 第 2 步：框选 → 识别
  // ---------------------------------------------------------------------------

  Future<void> _recognize() async {
    final bytes = _bytes;
    if (bytes == null) {
      return;
    }
    setState(() => _busy = true);
    try {
      if (!await ScheduleOcrService.isEngineAvailable()) {
        if (!mounted) {
          return;
        }
        setState(() {
          _busy = false;
          _errorKey = 'ocrEngineUnavailableTitle';
        });
        await _showEngineUnavailable();
        return;
      }
      final result = await ScheduleOcrService.recognizeToDrafts(bytes);
      if (!mounted) {
        return;
      }
      setState(() {
        _result = result;
        _busy = false;
        _stage = _Stage.review;
      });
    } on OcrEngineUnavailable catch (error) {
      AppLogger.e('本机识别引擎不可用', error: error);
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _errorKey = 'ocrEngineUnavailableTitle';
      });
      await _showEngineUnavailable();
    } catch (error, stack) {
      AppLogger.e('识别课表照片失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _errorKey = 'ocrWarnNoLesson';
      });
    }
  }

  /// 引擎不可用时的说明弹窗：把"为什么不联网也能做"和"现在怎么办"讲清楚。
  Future<void> _showEngineUnavailable() async {
    if (!mounted) {
      return;
    }
    final l10n = context.l10n;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.ocrEngineUnavailableTitle),
        content: Text(l10n.ocrEngineUnavailableBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 第 3 步：核对 → 导入
  // ---------------------------------------------------------------------------

  Future<void> _editDraft(int index) async {
    final result = _result;
    if (result == null) {
      return;
    }
    final draft = result.drafts[index];
    final controller = TextEditingController(text: draft.courseName);
    final saved = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.ocrRowEditTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: context.l10n.courseNameLabel,
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(context.l10n.save),
          ),
        ],
      ),
    );
    controller.dispose();
    final name = (saved ?? '').trim();
    if (name.isEmpty || !mounted) {
      return;
    }
    final drafts = List<OcrLessonDraft>.from(result.drafts);
    drafts[index] = draft.copyWith(courseName: name);
    setState(() => _result = result.copyWith(drafts: drafts));
  }

  void _removeDraft(int index) {
    final result = _result;
    if (result == null) {
      return;
    }
    AppMotion.tap();
    final drafts = List<OcrLessonDraft>.from(result.drafts)..removeAt(index);
    setState(() => _result = result.copyWith(drafts: drafts));
  }

  Future<void> _import() async {
    final result = _result;
    if (result == null || result.drafts.isEmpty) {
      return;
    }
    setState(() => _busy = true);
    try {
      final service = ScheduleOcrImportService(
        classRepository: context.read<ClassRepository>(),
        courseRepository: context.read<CourseRepository>(),
        lessonRepository: context.read<LessonRepository>(),
      );
      final outcome = await service.import(result.drafts);
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      showAppSnackBar(
        context,
        context.l10n.ocrImportDone(
          outcome.importedLessons,
          outcome.createdCourses,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (error, stack) {
      AppLogger.e('导入识别结果失败', error: error, stack: stack);
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      showAppSnackBar(context, context.l10n.operationFailed('$error'));
    }
  }

  void _reset() {
    AppMotion.tap();
    setState(() {
      _stage = _Stage.pick;
      _bytes = null;
      _result = null;
      _errorKey = null;
    });
  }

  // ---------------------------------------------------------------------------
  // 构建
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.ocrTitle),
        actions: <Widget>[
          if (_stage != _Stage.pick)
            IconButton(
              tooltip: l10n.ocrRecapture,
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _reset,
            ),
        ],
      ),
      body: _busy
          ? PulseLoading(message: l10n.ocrRecognizing)
          : switch (_stage) {
              _Stage.pick => _buildPick(l10n),
              _Stage.crop => _buildCrop(l10n),
              _Stage.review => _buildReview(l10n),
            },
      bottomNavigationBar: _buildBottomBar(l10n),
    );
  }

  Widget? _buildBottomBar(AppLocalizations l10n) {
    return switch (_stage) {
      _Stage.pick => null,
      _Stage.crop => _BottomBar(
          primaryLabel: l10n.ocrCropConfirm,
          onPrimary: _recognize,
        ),
      _Stage.review => _BottomBar(
          primaryLabel: l10n.ocrImport,
          onPrimary:
              (_result?.drafts.isEmpty ?? true) ? null : _import,
        ),
    };
  }

  // ----- 第 1 步视图 -----

  Widget _buildPick(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListView(
      padding: const EdgeInsets.only(bottom: AppConstants.spaceXl),
      children: <Widget>[
        const SizedBox(height: AppConstants.spaceM),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceL),
          child: const _OcrHero(),
        ),
        const SizedBox(height: AppConstants.spaceL),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceL),
          child: FilledButton.icon(
            onPressed: () => _pick(ImageSource.camera),
            icon: const Icon(Icons.photo_camera_outlined, size: 18),
            label: Text(l10n.ocrFromCamera),
          ),
        ),
        const SizedBox(height: AppConstants.spaceM),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceL),
          child: OutlinedButton.icon(
            onPressed: () => _pick(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined, size: 18),
            label: Text(l10n.ocrFromGallery),
          ),
        ),
        if (_errorKey != null) ...<Widget>[
          const SizedBox(height: AppConstants.spaceM),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceL),
            child: _TipBanner(
              icon: Icons.error_outline_rounded,
              text: _errorText(l10n, _errorKey!),
              tone: _TipTone.error,
            ),
          ),
        ],
        const SizedBox(height: AppConstants.spaceL),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceL),
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.lightbulb_outline_rounded,
                      size: 17,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: AppConstants.spaceS),
                    Expanded(
                      child: Text(
                        l10n.ocrCropHint,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppConstants.spaceM),
                _bullet(theme, l10n.ocrPickPhotoHint),
                _bullet(theme, l10n.ocrResultTitle),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppConstants.spaceM),
        // 机型适配说明（第 12 轮）：国产安卓 / 鸿蒙 / iOS 三条分别交代清楚。
        // 用户规格："华为是鸿蒙系统，可能得额外标注" + "给苹果系统留给备注和提示，
        // 后续用到再开发" —— 这里就是那两条备注唯一的落点。
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceL),
          child: const _DeviceSupportCard(),
        ),
      ],
    );
  }

  // ----- 第 2 步视图 -----

  Widget _buildCrop(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final bytes = _bytes!;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.spaceL,
            AppConstants.spaceM,
            AppConstants.spaceL,
            AppConstants.spaceS,
          ),
          child: Text(
            l10n.ocrCropHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppConstants.spaceL),
            child: Center(
              child: CropSelector(
                imageBytes: bytes,
                crop: _crop,
                onChanged: (value) => setState(() => _crop = value),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.spaceL,
            0,
            AppConstants.spaceL,
            AppConstants.spaceS,
          ),
          child: TextButton.icon(
            onPressed: () => setState(
              () => _crop = const Rect.fromLTRB(0.06, 0.08, 0.94, 0.92),
            ),
            icon: const Icon(Icons.crop_free_rounded, size: 18),
            label: Text(l10n.ocrCropReset),
          ),
        ),
      ],
    );
  }

  // ----- 第 3 步视图 -----

  Widget _buildReview(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final result = _result!;
    final drafts = result.drafts;

    return ListView(
      padding: const EdgeInsets.only(bottom: AppConstants.spaceXl),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.spaceL,
            AppConstants.spaceM,
            AppConstants.spaceL,
            AppConstants.spaceS,
          ),
          child: Text(
            l10n.ocrResultSummary(
              drafts.length,
              result.distinctCourseCount,
              result.dayCount,
            ),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (_confidenceKey(result) != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.spaceL,
              0,
              AppConstants.spaceL,
              AppConstants.spaceS,
            ),
            child: _TipBanner(
              icon: result.confidence >= 70
                  ? Icons.verified_outlined
                  : Icons.warning_amber_rounded,
              text: _confidenceText(l10n, result.confidence),
              tone: result.confidence >= 70
                  ? _TipTone.good
                  : (result.confidence >= 45 ? _TipTone.warn : _TipTone.error),
            ),
          ),
        for (final key in result.warnings)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.spaceL,
              0,
              AppConstants.spaceL,
              AppConstants.spaceXs,
            ),
            child: _TipBanner(
              icon: Icons.info_outline_rounded,
              text: _warnText(l10n, key),
              tone: _TipTone.warn,
            ),
          ),
        if (drafts.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppConstants.spaceL),
            child: AppCard(
              child: Text(
                l10n.ocrWarnNoLesson,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          )
        else
          for (var i = 0; i < drafts.length; i++)
            StaggeredEntrance(
              index: i,
              child: _DraftRow(
                draft: drafts[i],
                onTap: () => _editDraft(i),
                onDelete: () => _removeDraft(i),
              ),
            ),
      ],
    );
  }

  String? _confidenceKey(ScheduleOcrResult result) {
    if (result.drafts.isEmpty) {
      return null;
    }
    return 'confidence';
  }

  String _confidenceText(AppLocalizations l10n, int confidence) {
    if (confidence >= 70) {
      return l10n.ocrConfidenceHigh;
    }
    if (confidence >= 45) {
      return l10n.ocrConfidenceMedium;
    }
    return l10n.ocrConfidenceLow;
  }

  String _warnText(AppLocalizations l10n, String key) => switch (key) {
        'ocrWarnNoWeekday' => l10n.ocrWarnNoWeekday,
        'ocrWarnPartialWeekday' => l10n.ocrWarnPartialWeekday,
        'ocrWarnNoPeriod' => l10n.ocrWarnNoPeriod,
        _ => l10n.ocrWarnNoLesson,
      };

  String _errorText(AppLocalizations l10n, String key) => switch (key) {
        'ocrNoPhotoPermission' => l10n.ocrNoPhotoPermission,
        'ocrEngineUnavailableTitle' => l10n.ocrEngineUnavailable,
        'ocrWarnNoLesson' => l10n.ocrWarnNoLesson,
        _ => l10n.ocrNoPhoto,
      };

  Widget _bullet(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spaceXs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: AppConstants.spaceS),
          Expanded(
            child: Text(text, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

/// 一张识别结果的核对行：周几 · 第 N 节 · 课程名（点击可改，右侧可删）。
class _DraftRow extends StatelessWidget {
  const _DraftRow({
    required this.draft,
    required this.onTap,
    required this.onDelete,
  });

  final OcrLessonDraft draft;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spaceL,
        AppConstants.spaceXs,
        AppConstants.spaceL,
        AppConstants.spaceXs,
      ),
      child: AppCard(
        padding: EdgeInsets.zero,
        elevated: false,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spaceM,
            vertical: AppConstants.spaceS,
          ),
          child: Row(
            children: <Widget>[
              // 周几 + 节次（固定宽，让下面的课程名对齐成一列）
              SizedBox(
                width: 84,
                child: Text(
                  '${l10n.weekdayShort(draft.weekday)} · '
                  '${l10n.periodIndexLabel(draft.periodIndex)}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppConstants.spaceS),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      draft.courseName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (_subtitle(draft) != null)
                      Text(
                        _subtitle(draft)!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: l10n.delete,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _subtitle(OcrLessonDraft draft) {
    final parts = <String>[
      if (draft.startTime != null) '${draft.startTime}-${draft.endTime}',
      if ((draft.room ?? '').isNotEmpty) draft.room!,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

/// 顶部那张解释「为什么不用 AI 服务商」的卡片。
class _OcrHero extends StatelessWidget {
  const _OcrHero();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const accent = <Color>[Color(0xFF4FC3B0), Color(0xFF00897B)];
    return AppCard(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          accent.first.withValues(alpha: 0.18),
          accent.last.withValues(alpha: 0.05),
        ],
      ),
      borderColor: accent.first.withValues(alpha: 0.30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: accent,
              ),
              borderRadius: AppRadii.tileAll,
            ),
            child: const Icon(
              Icons.document_scanner_outlined,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(height: AppConstants.spaceM),
          Text(
            l10n.ocrEntryTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.ocrEntryDesc,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: AppConstants.spaceM),
          Row(
            children: <Widget>[
              Icon(
                Icons.wifi_off_rounded,
                size: 14,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.ocrRecognizingHint,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 机型适配卡片（第 12 轮）。
///
/// 用户规格："目标机型：安卓最近三代版本，可以带 Google 服务，但是都用在国产手机上。
/// 小米、OPPO、vivo 等，华为是鸿蒙系统，可能得额外标注。给苹果系统留给备注和提示，
/// 后续用到再开发。"
///
/// 三条各自给一个明确的结论（能用 / 暂不支持 / 已预留），
/// 而不是笼统写一句"部分机型不支持"——老师打开就知道自己这台行不行、
/// 不行的话替代路径是哪条。
class _DeviceSupportCard extends StatelessWidget {
  const _DeviceSupportCard();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.devices_other_outlined,
                size: 17,
                color: scheme.primary,
              ),
              const SizedBox(width: AppConstants.spaceS),
              Expanded(
                child: Text(
                  l10n.ocrDeviceTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spaceM),
          _DeviceRow(
            icon: Icons.android_rounded,
            tone: _DeviceTone.ok,
            label: 'Android',
            text: l10n.ocrDeviceAndroid,
          ),
          const SizedBox(height: AppConstants.spaceM),
          _DeviceRow(
            icon: Icons.phonelink_ring_outlined,
            tone: _DeviceTone.warn,
            label: 'HarmonyOS',
            text: l10n.ocrDeviceHarmony,
          ),
          const SizedBox(height: AppConstants.spaceM),
          _DeviceRow(
            icon: Icons.phone_iphone_rounded,
            tone: _DeviceTone.pending,
            label: 'iOS',
            text: l10n.ocrDeviceIos,
          ),
        ],
      ),
    );
  }
}

enum _DeviceTone { ok, warn, pending }

/// 适配说明里的一行：图标胶囊 + 平台名 + 结论。
class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.icon,
    required this.tone,
    required this.label,
    required this.text,
  });

  final IconData icon;
  final _DeviceTone tone;
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (Color bg, Color fg) = switch (tone) {
      _DeviceTone.ok => (scheme.primaryContainer, scheme.onPrimaryContainer),
      _DeviceTone.warn => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      _DeviceTone.pending => (
          scheme.surfaceContainerHigh,
          scheme.onSurfaceVariant,
        ),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: bg.withValues(alpha: 0.8),
            borderRadius: AppRadii.smallAll,
          ),
          child: Icon(icon, size: 16, color: fg),
        ),
        const SizedBox(width: AppConstants.spaceS),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _TipTone { good, warn, error }

/// 一条左图标 + 淡底色的提示带。
class _TipBanner extends StatelessWidget {
  const _TipBanner({
    required this.icon,
    required this.text,
    required this.tone,
  });

  final IconData icon;
  final String text;
  final _TipTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color bg, Color fg) = switch (tone) {
      _TipTone.good => (
          scheme.primaryContainer.withValues(alpha: 0.55),
          scheme.onPrimaryContainer,
        ),
      _TipTone.warn => (
          scheme.tertiaryContainer.withValues(alpha: 0.55),
          scheme.onTertiaryContainer,
        ),
      _TipTone.error => (
          scheme.errorContainer.withValues(alpha: 0.6),
          scheme.onErrorContainer,
        ),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spaceM,
        vertical: AppConstants.spaceS,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadii.smallAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: AppConstants.spaceS),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: fg,
                    height: 1.35,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 底部主操作条（左次要 / 右主要，与详情弹窗的按钮位一致）。
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.primaryLabel, required this.onPrimary});

  final String primaryLabel;
  final VoidCallback? onPrimary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(
        AppConstants.spaceL,
        0,
        AppConstants.spaceL,
        AppConstants.spaceM,
      ),
      child: Row(
        children: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: Text(context.l10n.cancel),
          ),
          const Spacer(),
          FilledButton(
            onPressed: onPrimary,
            style: FilledButton.styleFrom(
              // 全局 minimumSize 宽度是 infinity，放 Row 里会抛无限宽约束
              minimumSize: const Size(0, 48),
            ),
            child: Text(primaryLabel, style: theme.textTheme.labelLarge),
          ),
        ],
      ),
    );
  }
}
