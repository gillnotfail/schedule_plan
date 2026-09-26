import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_plan/core/utils/pinyin_utils.dart';

void main() {
  group('PinyinUtils', () {
    test('常见姓氏取首字母', () {
      expect(PinyinUtils.initialOf('张'), 'z');
      expect(PinyinUtils.initialOf('李'), 'l');
      expect(PinyinUtils.initialOf('王'), 'w');
      expect(PinyinUtils.initialOf('欧'), 'o');
    });

    test('未命中汉字回退为原字符（不抛异常）', () {
      final unknown = '㐀';
      expect(PinyinUtils.initialOf(unknown), unknown.toLowerCase());
    });

    test('sortKey 对每个字符生成键（未收录汉字回退原字符，保证排序稳定）', () {
      expect(PinyinUtils.sortKey('张三'), 'z三');
      expect(PinyinUtils.sortKey('李明'), 'lm');
      expect(PinyinUtils.sortKey(''), '');
    });

    test('非中文（英文名）保持原样参与排序', () {
      expect(PinyinUtils.sortKey('Alice'), 'alice');
    });

    test('compareByName 按拼音升序', () {
      final names = <String>['赵六', 'Alice', '李四', '安琪', '王五'];
      final sorted = [...names]..sort(PinyinUtils.compareByName);
      // a(Alice) < a(安琪) < l(李四) < w(王五) < z(赵六)
      expect(sorted.first, 'Alice');
      expect(sorted.last, '赵六');
      expect(sorted.indexOf('李四'), lessThan(sorted.indexOf('王五')));
    });

    test('比较结果稳定：反序比较为正', () {
      expect(PinyinUtils.compareByName('王五', '李四'), greaterThan(0));
      expect(PinyinUtils.compareByName('李四', '王五'), lessThan(0));
      expect(PinyinUtils.compareByName('李四', '李四'), 0);
    });
  });
}
