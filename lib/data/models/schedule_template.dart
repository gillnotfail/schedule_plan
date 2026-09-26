import 'package:schedule_plan/core/utils/time_utils.dart';

/// 模板节次类型（readme 3.2 表）。
enum PeriodType {
  normal,
  lunchBreak,
  recess,
  selfStudy,
  other;

  String get storageKey => switch (this) {
        PeriodType.normal => 'normal',
        PeriodType.lunchBreak => 'lunch_break',
        PeriodType.recess => 'recess',
        PeriodType.selfStudy => 'self_study',
        PeriodType.other => 'other',
      };

  static PeriodType fromStorage(String? value) => PeriodType.values.firstWhere(
        (item) => item.storageKey == value,
        orElse: () => PeriodType.normal,
      );

  /// 非 normal 的时段在时间轴上以浅色条带标注且不可点击（模块一 1.4 第 6 条）。
  bool get isBreak => this != PeriodType.normal;
}

/// 作息模板节次（readme 3.2 表 template_period）。
class TemplatePeriod {
  const TemplatePeriod({
    this.id,
    required this.templateId,
    required this.weekday,
    required this.periodIndex,
    this.periodType = PeriodType.normal,
    required this.startTime,
    required this.endTime,
    this.label,
  });

  final int? id;
  final int templateId;

  /// 1 = 周一 ... 7 = 周日
  final int weekday;

  /// 模板内部节次编号（相对模板，不是全局节次）
  final int periodIndex;
  final PeriodType periodType;

  /// "HH:mm" 本地时间字符串，不存绝对时间戳（避免时区/夏令时问题）
  final String startTime;
  final String endTime;
  final String? label;

  int get startMinutes => TimeUtils.parseMinutes(startTime);

  int get endMinutes => TimeUtils.parseMinutes(endTime);

  TemplatePeriod copyWith({
    int? id,
    int? templateId,
    int? weekday,
    int? periodIndex,
    PeriodType? periodType,
    String? startTime,
    String? endTime,
    String? label,
  }) {
    return TemplatePeriod(
      id: id ?? this.id,
      templateId: templateId ?? this.templateId,
      weekday: weekday ?? this.weekday,
      periodIndex: periodIndex ?? this.periodIndex,
      periodType: periodType ?? this.periodType,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      label: label ?? this.label,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        if (id != null) 'id': id,
        'template_id': templateId,
        'weekday': weekday,
        'period_index': periodIndex,
        'period_type': periodType.storageKey,
        'start_time': startTime,
        'end_time': endTime,
        'label': label,
      };

  static TemplatePeriod fromMap(Map<String, Object?> map) => TemplatePeriod(
        id: map['id'] as int?,
        templateId: map['template_id'] as int,
        weekday: map['weekday'] as int,
        periodIndex: map['period_index'] as int,
        periodType: PeriodType.fromStorage(map['period_type'] as String?),
        startTime: map['start_time'] as String,
        endTime: map['end_time'] as String,
        label: map['label'] as String?,
      );
}

/// 作息模板（readme 3.1 表 schedule_template）。
class ScheduleTemplate {
  const ScheduleTemplate({
    this.id,
    required this.name,
    this.isDefault = false,
    required this.createdAt,
    required this.updatedAt,
    this.boundClassCount = 0,
  });

  final int? id;
  final String name;

  /// 全库仅一条为 1，写入时需在事务内先清除其他记录
  final bool isDefault;
  final int createdAt;
  final int updatedAt;

  /// 列表页展示用：绑定的班级数量（非表字段，联查得出）
  final int boundClassCount;

  ScheduleTemplate copyWith({
    int? id,
    String? name,
    bool? isDefault,
    int? createdAt,
    int? updatedAt,
    int? boundClassCount,
  }) {
    return ScheduleTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      boundClassCount: boundClassCount ?? this.boundClassCount,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        if (id != null) 'id': id,
        'name': name,
        'is_default': isDefault ? 1 : 0,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  static ScheduleTemplate fromMap(Map<String, Object?> map, {int boundClassCount = 0}) =>
      ScheduleTemplate(
        id: map['id'] as int?,
        name: map['name'] as String,
        isDefault: (map['is_default'] as int? ?? 0) == 1,
        createdAt: map['created_at'] as int,
        updatedAt: map['updated_at'] as int,
        boundClassCount:
            map.containsKey('bound_class_count') ? (map['bound_class_count'] as int? ?? 0) : boundClassCount,
      );
}
