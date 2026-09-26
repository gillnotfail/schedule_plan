import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:schedule_plan/core/utils/color_utils.dart';

void main() {
  const fallback = Color(0xFF112233);

  group('parseHexColor', () {
    test('解析 8 位 ARGB 班级色', () {
      expect(parseHexColor('FF26A69A', fallback), const Color(0xFF26A69A));
    });

    test('兼容带 # 的写法', () {
      expect(parseHexColor('#26A69A', fallback), const Color(0xFF26A69A));
    });

    test('6 位 RGB 自动补不透明，不会变成全透明', () {
      // 只给 6 位时 int.parse 出来的 alpha 是 0，不补 0xFF 就会「有这个色但看不见」
      expect(parseHexColor('26A69A', fallback).a, 1.0);
    });

    test('空值 / 非法值回落到兜底色而不是崩', () {
      expect(parseHexColor(null, fallback), fallback);
      expect(parseHexColor('', fallback), fallback);
      expect(parseHexColor('这不是颜色', fallback), fallback);
    });
  });
}
