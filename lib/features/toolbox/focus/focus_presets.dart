import 'package:flutter/material.dart';

import 'package:schedule_plan/core/l10n/l10n_extensions.dart';

/// 专注的三大类（用户规格：健康 / 工作效率 / 生活应用）。
///
/// **落库的是类别 id**（`health` / `work` / `life`），不是中文名 ——
/// 名字是给人看的、会随语言变；类别是给以后按类回看统计用的、不该变。
/// 和 [FocusPreset.id] 同一个道理，见那边的说明。
enum FocusCategory {
  health('health', Icons.favorite_outline),
  work('work', Icons.work_outline),
  life('life', Icons.local_cafe_outlined);

  const FocusCategory(this.storageKey, this.icon);

  /// 存进数据库的稳定标识。
  final String storageKey;

  /// 选类别时用的小图标。
  final IconData icon;

  /// 读不认识的类别（老版本写的、手工改的）就返回 null，当"没选"处理。
  static FocusCategory? fromStorage(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    for (final item in FocusCategory.values) {
      if (item.storageKey == value) {
        return item;
      }
    }
    return null;
  }
}

/// 一个预设的专注名。
///
/// [id] 是稳定标识（如 `meditation`），**存进数据库的是它**；显示名走
/// 本地化文案，换语言时会跟着翻。用户自己敲的名字不在这套体系里 ——
/// 那种情况直接把原文存进 `label`，渲染时查不到 id 就按普通文本显示。
@immutable
class FocusPreset {
  const FocusPreset({required this.id, required this.category});

  final String id;
  final FocusCategory category;
}

/// 预设清单。顺序即界面顺序，[FocusCategory] 的声明顺序即分组的先后。
///
/// 只收用户点名的那些场景；没覆盖到的情况走"自己写一个"，
/// 不硬凑 —— 预设越长越像表单，反而不想用。
const List<FocusPreset> focusPresets = <FocusPreset>[
  FocusPreset(id: 'exercise', category: FocusCategory.health),
  FocusPreset(id: 'meditation', category: FocusCategory.health),
  FocusPreset(id: 'breathing', category: FocusCategory.health),
  FocusPreset(id: 'pomodoro', category: FocusCategory.work),
  FocusPreset(id: 'meeting', category: FocusCategory.work),
  FocusPreset(id: 'speech', category: FocusCategory.work),
  FocusPreset(id: 'handwriting', category: FocusCategory.life),
  FocusPreset(id: 'cleaning', category: FocusCategory.life),
  FocusPreset(id: 'rest', category: FocusCategory.life),
  FocusPreset(id: 'cooking', category: FocusCategory.life),
  FocusPreset(id: 'gaming', category: FocusCategory.life),
];

/// 某类别下的预设。
List<FocusPreset> presetsOf(FocusCategory category) =>
    focusPresets.where((item) => item.category == category).toList();

/// 预设 id 对应的本地化名字。
///
/// **查不到就返回 null**（调方按普通文本处理）—— 认不出的 id 可能来自
/// 更高版本写的记录，宁可显示成原文也不能抛异常。
String? focusPresetLabel(BuildContext context, String id) {
  final l10n = context.l10n;
  switch (id) {
    case 'exercise':
      return l10n.focusPresetExercise;
    case 'meditation':
      return l10n.focusPresetMeditation;
    case 'breathing':
      return l10n.focusPresetBreathing;
    case 'pomodoro':
      return l10n.focusPresetPomodoro;
    case 'meeting':
      return l10n.focusPresetMeeting;
    case 'speech':
      return l10n.focusPresetSpeech;
    case 'handwriting':
      return l10n.focusPresetHandwriting;
    case 'cleaning':
      return l10n.focusPresetCleaning;
    case 'rest':
      return l10n.focusPresetRest;
    case 'cooking':
      return l10n.focusPresetCooking;
    case 'gaming':
      return l10n.focusPresetGaming;
    default:
      return null;
  }
}

/// 类别名的本地化。
String focusCategoryLabel(BuildContext context, FocusCategory category) {
  final l10n = context.l10n;
  switch (category) {
    case FocusCategory.health:
      return l10n.focusCategoryHealth;
    case FocusCategory.work:
      return l10n.focusCategoryWork;
    case FocusCategory.life:
      return l10n.focusCategoryLife;
  }
}

/// 把落库的 [label] 渲染成人看的样子。
///
/// 先当 id 查本地化文案；查不到（用户自己写的、或来自更高版本的 id）
/// 就原样返回 —— 这是 **历史记录** 的显示口径，别在这里做任何裁剪。
String focusLabelText(BuildContext context, String? label) {
  if (label == null || label.isEmpty) {
    return '';
  }
  return focusPresetLabel(context, label) ?? label;
}
