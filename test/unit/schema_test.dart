import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_plan/data/db/schema.dart';

const List<String> _expectedTables = <String>[
  'schedule_template',
  'template_period',
  'class',
  'course',
  'course_class',
  'lesson',
  'student',
  'attendance_record',
  // v5：课程级长期状态（休学 / 免修，点一次管 180 天）
  'student_course_status',
  'student_tag_record',
  'todo',
  'note',
  'schedule_event',
  'focus_session',
  'import_log',
  'llm_provider_config',
  'app_settings',
  // v7：节假日 / 调休安排的本地缓存（联网取回的年度数据，覆盖内置表缺的年份）
  'holiday_day',
];

/// 从建表语句中抽出表名。
String? _tableNameOf(String statement) {
  final match = RegExp(
    r'CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\s+(\w+)',
    caseSensitive: false,
  ).firstMatch(statement);
  return match?.group(1);
}

void main() {
  group('DatabaseSchema', () {
    test('共 18 张表（含 course_class 关联表、v5 长期状态表与 v7 节假日缓存），与 readme 第三章一致', () {
      final names = DatabaseSchema.createTables
          .map(_tableNameOf)
          .whereType<String>()
          .toList();
      expect(names.length, 18);
      expect(names, _expectedTables);
    });

    test('每张表都有主键', () {
      for (final statement in DatabaseSchema.createTables) {
        expect(
          statement.toUpperCase().contains('PRIMARY KEY'),
          isTrue,
          reason: '${_tableNameOf(statement)} 缺少 PRIMARY KEY',
        );
      }
    });

    test('所有外键都显式声明 ON DELETE 策略（禁止裸外键）', () {
      final fkPattern = RegExp(r'REFERENCES\s+\w+\(id\)', caseSensitive: false);
      for (final statement in DatabaseSchema.createTables) {
        final table = _tableNameOf(statement);
        for (final match in fkPattern.allMatches(statement)) {
          final tail = statement.substring(match.end);
          expect(
            tail.trimLeft().toUpperCase().startsWith('ON DELETE'),
            isTrue,
            reason: '$table 中存在未声明 ON DELETE 策略的外键',
          );
        }
      }
    });

    test('建表顺序满足依赖：被引用的表先建', () {
      final names = DatabaseSchema.createTables
          .map(_tableNameOf)
          .whereType<String>()
          .toList();
      final order = <String, int>{
        for (var i = 0; i < names.length; i++) names[i]: i,
      };
      for (final statement in DatabaseSchema.createTables) {
        final table = _tableNameOf(statement)!;
        for (final match in
            RegExp(r'REFERENCES\s+(\w+)\(id\)', caseSensitive: false)
                .allMatches(statement)) {
          final referenced = match.group(1)!;
          if (!order.containsKey(referenced)) {
            continue;
          }
          expect(
            order[referenced]!,
            lessThan(order[table]!),
            reason: '$table 引用了尚未创建的 $referenced',
          );
        }
      }
    });

    test('weekday 字段带 1~7 取值约束', () {
      final tablesWithWeekday = <String>['template_period', 'lesson'];
      for (final statement in DatabaseSchema.createTables) {
        final table = _tableNameOf(statement);
        if (!tablesWithWeekday.contains(table)) {
          continue;
        }
        expect(
          statement.contains('CHECK(weekday BETWEEN 1 AND 7)'),
          isTrue,
          reason: '$table 的 weekday 缺少取值范围约束',
        );
      }
    });

    test('考勤记录唯一约束防止同一学生同一节课同一天重复记录', () {
      final statement = DatabaseSchema.createTables.firstWhere(
        (item) => _tableNameOf(item) == 'attendance_record',
      );
      expect(statement.contains('UNIQUE(student_id, lesson_id, date)'), isTrue);
    });

    test('课程长期状态（休学/免修）同一学生在同一门课只有一条', () {
      final statement = DatabaseSchema.createTables.firstWhere(
        (item) => _tableNameOf(item) == 'student_course_status',
      );
      expect(statement.contains('UNIQUE(student_id, course_id)'), isTrue);
      // 生效区间靠 start_date / end_date 两个 "YYYY-MM-DD" 字符串承载
      expect(statement.contains('start_date TEXT NOT NULL'), isTrue);
      expect(statement.contains('end_date TEXT NOT NULL'), isTrue);
    });

    test('课程长期状态的建表语句只有一份（建库与迁移共用）', () {
      // 迁移 v4 -> v5 执行的就是 createTables 里那一段，
      // 两处各写一份迟早会漂（比如这里加了列、迁移里没加）。
      expect(
        DatabaseSchema.createTables.contains(
          DatabaseSchema.createCourseStudentStatusTable,
        ),
        isTrue,
      );
    });

    test('模板节次唯一约束防止同模板同天重复节次编号', () {
      final statement = DatabaseSchema.createTables.firstWhere(
        (item) => _tableNameOf(item) == 'template_period',
      );
      expect(
        statement.contains('UNIQUE(template_id, weekday, period_index)'),
        isTrue,
      );
    });

    test('readme 3.5 要求的两条课表索引均已建立', () {
      expect(
        DatabaseSchema.createIndexes.any(
          (item) => item.contains('idx_lesson_teacher_weekday'),
        ),
        isTrue,
      );
      expect(
        DatabaseSchema.createIndexes.any(
          (item) => item.contains('idx_lesson_class_slot'),
        ),
        isTrue,
      );
    });

    test('所有索引使用 IF NOT EXISTS，可重复执行', () {
      for (final statement in DatabaseSchema.createIndexes) {
        expect(statement.contains('IF NOT EXISTS'), isTrue);
      }
    });

    test('版本号为正整数且随迁移逻辑同步声明', () {
      expect(DatabaseSchema.version, greaterThan(0));
    });
  });
}
