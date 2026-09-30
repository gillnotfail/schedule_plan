import 'package:flutter/painting.dart';

/// 十六进制色值 → [Color]。
///
/// 库里班级色存的是 `FF26A69A` 这类字符串（也能兼容带 `#` 的写法）。
/// 课表页、班级列表、班级详情、学生头像、课程表单都要做同一份解析——
/// 各自抄一遍迟早会出现「同一个班在不同的地方颜色不一样」。
///
/// [fallback] 用于空值或解析失败，调用方一般传主题的 primary。
Color parseHexColor(String? hex, Color fallback) {
  if (hex == null || hex.isEmpty) {
    return fallback;
  }
  final value = int.tryParse(hex.replaceAll('#', ''), radix: 16);
  if (value == null) {
    return fallback;
  }
  // 只给了 6 位（RGB）时补上不透明度，避免变成全透明看不见
  final opaque = hex.replaceAll('#', '').length <= 6 ? value | 0xFF000000 : value;
  return Color(opaque);
}

/// 课程 / 班级色的**实心填充**版本 —— 课表格子、错峰曲线课块「整格铺满」时用它。
///
/// 为什么需要压暗：色板（`kClassPalette`）里有一批偏亮的色 —— 浅蓝 `FF29B6F6`、
/// 黄绿 `FF7CB342`、亮橙 `FFFF7043`。原样铺满再把白色文字压上去，对比度只有
/// 2.2~2.9（WCAG 大字门槛是 3.0），字会糊在底色里。所以这里把**过亮**的色按
/// HSL 逐档降低明度，直到白色文字的对比度达到 [minContrast] 为止。
///
/// 两条自我保护：
/// - **只降不升**：本来就够深的色（`FF8E24AA`、`FF5E35B1`、`FF795548`…）原样
///   返回，老师选的颜色不会被"提亮"成另一个色；
/// - 降到 [minLightness] 就收手 —— 宁可对比度差一点点，也不要把颜色压成黑块。
///
/// 之所以放在这里而不是各页面各写一份：同一门课在**表格档**和**曲线档**必须
/// 深浅一致（老师两个视图来回切），两处各算一遍迟早会漂。
Color solidFillColor(
  Color base, {
  double minContrast = 3.2,
  double minLightness = 0.30,
}) {
  if (whiteContrastRatio(base) >= minContrast) {
    return base;
  }
  var hsl = HSLColor.fromColor(base);
  var current = base;
  // 每档降 2% 明度；色板 14 色实测最多降 7 档就达标，循环上限只是保险丝。
  for (var step = 0; step < 40; step++) {
    if (whiteContrastRatio(current) >= minContrast ||
        hsl.lightness <= minLightness) {
      break;
    }
    hsl = hsl.withLightness((hsl.lightness - 0.02).clamp(0.0, 1.0));
    current = hsl.toColor();
  }
  return current;
}

/// 白色文字压在 [background] 上的对比度（WCAG 2.x 口径，1.0 ~ 21.0）。
///
/// 3.0 = 大字（≥18.66px 加粗）的最低门槛。课程名是 11.5px 的 w800，视觉重量
/// 落在这一档，所以 [solidFillColor] 取 3.2 留一点余量。
double whiteContrastRatio(Color background) =>
    1.05 / (background.computeLuminance() + 0.05);
