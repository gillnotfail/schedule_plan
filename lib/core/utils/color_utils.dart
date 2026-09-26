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
