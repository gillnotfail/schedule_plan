import 'package:flutter_test/flutter_test.dart';

import 'package:schedule_plan/core/utils/file_naming.dart';

void main() {
  final now = DateTime(2026, 11, 12, 20, 38);

  group('exportStamp', () {
    test('导出时间按 年月日-时分 输出', () {
      expect(exportStamp(now), '20261112-2038');
    });

    test('个位数月日与时分补零', () {
      expect(exportStamp(DateTime(2027, 1, 5, 9, 7)), '20270105-0907');
    });
  });

  group('buildExportFileName', () {
    test('课程维度：时间-课程名-出勤情况', () {
      expect(
        buildExportFileName(kind: '出勤情况', subject: '数学', now: now),
        '20261112-2038-数学-出勤情况.xlsx',
      );
    });

    test('学生维度：时间-学生名-出勤记录', () {
      expect(
        buildExportFileName(kind: '出勤记录', subject: '张三', now: now),
        '20261112-2038-张三-出勤记录.xlsx',
      );
    });

    test('没有对象时不留空段', () {
      expect(
        buildExportFileName(kind: '学生追踪', now: now),
        '20261112-2038-学生追踪.xlsx',
      );
      expect(
        buildExportFileName(kind: '出勤情况', subject: '   ', now: now),
        '20261112-2038-出勤情况.xlsx',
      );
    });

    test('备份文件也能用同一套口径（json 扩展名）', () {
      expect(
        buildExportFileName(
          subject: '考勤清理备份',
          kind: '截止2026-05-16',
          extension: 'json',
          now: now,
        ),
        '20261112-2038-考勤清理备份-截止2026-05-16.json',
      );
    });
  });

  group('sanitizeFilePart', () {
    test('路径分隔符替换掉，不会建出子目录', () {
      expect(sanitizeFilePart('数学/物理'), '数学-物理');
      expect(sanitizeFilePart(r'C:\课表\数学'), 'C-课表-数学');
    });

    test('Windows 非法字符一律换横线', () {
      expect(sanitizeFilePart('3班: 周二*'), '3班-周二');
    });

    test('连续横线压成一个', () {
      expect(sanitizeFilePart('数学//物理'), '数学-物理');
    });

    test('首尾的点与横线去掉（Windows 会吞掉或变成隐藏文件）', () {
      expect(sanitizeFilePart(' .张三. '), '张三');
    });

    test('超长课程名截断到 40 字以内', () {
      final long = '一' * 80;
      expect(sanitizeFilePart(long).length, 40);
    });

    test('全是非法字符时得到空串，交由调用方跳过', () {
      expect(sanitizeFilePart('///'), '');
    });
  });
}
