import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:schedule_plan/core/utils/color_utils.dart';
import 'package:schedule_plan/features/management/class_form_sheet.dart'
    show kClassPalette;

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

  group('solidFillColor', () {
    // 色板（`kClassPalette`）就是老师真正能选到的全部颜色，所以直接拿它当护栏：
    // 以后往里加一个更浅的色，这条会立刻红，而不是等老师反馈"字看不清"。
    test('色板里每一个颜色铺满后，白色文字都够看得清', () {
      for (final hex in kClassPalette) {
        final fill = solidFillColor(parseHexColor(hex, fallback));
        expect(
          whiteContrastRatio(fill),
          greaterThanOrEqualTo(3.2),
          reason: '$hex 铺满之后白字对比度不足',
        );
      }
    });

    test('本来就够深的颜色原样返回，不会被提亮成另一个色', () {
      const deep = Color(0xFF5E35B1);
      expect(solidFillColor(deep), deep);
    });

    test('压暗只动明度，色相与饱和度不变', () {
      const base = Color(0xFF29B6F6);
      final fill = solidFillColor(base);
      final before = HSLColor.fromColor(base);
      final after = HSLColor.fromColor(fill);
      expect(after.hue, closeTo(before.hue, 0.5));
      expect(after.saturation, closeTo(before.saturation, 0.02));
      expect(after.lightness, lessThan(before.lightness));
    });

    test('白字永远达不到门槛的极端浅色也不会被压成黑块', () {
      // 纯黄在白字下怎么压都到不了 3.2，靠 minLightness 兜住，不无限下压
      final fill = solidFillColor(const Color(0xFFFFFF00));
      expect(HSLColor.fromColor(fill).lightness, greaterThan(0.29));
    });
  });

  group('whiteContrastRatio', () {
    test('白底 1.0、黑底 21.0（WCAG 的两个端点）', () {
      expect(whiteContrastRatio(const Color(0xFFFFFFFF)), closeTo(1.0, 0.01));
      expect(whiteContrastRatio(const Color(0xFF000000)), closeTo(21.0, 0.01));
    });
  });
}
