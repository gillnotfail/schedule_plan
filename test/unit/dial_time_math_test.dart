import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:schedule_plan/core/widgets/dial_time_picker.dart';

/// 12 小时表盘 ↔ 24 小时制的换算。
///
/// 这块错了不会报错，只会静默把「下午 3 点」存成「凌晨 3 点」，
/// 所以每个边界（0 点 / 12 点 / 23 点）都单独钉一遍。
void main() {
  group('DialTimeMath 12/24 小时换算', () {
    test('24 小时制换算成表盘上的 1~12', () {
      expect(DialTimeMath.hour12Of(0), 12);
      expect(DialTimeMath.hour12Of(12), 12);
      expect(DialTimeMath.hour12Of(8), 8);
      expect(DialTimeMath.hour12Of(13), 1);
      expect(DialTimeMath.hour12Of(23), 11);
    });

    test('表盘读数拼回 24 小时制', () {
      expect(DialTimeMath.combine(hour12: 8, pm: false, minute: 0), 8);
      // 上午 12 点 = 00:xx，下午 12 点 = 12:xx
      expect(DialTimeMath.combine(hour12: 12, pm: false, minute: 0), 0);
      expect(DialTimeMath.combine(hour12: 12, pm: true, minute: 0), 12);
      expect(DialTimeMath.combine(hour12: 1, pm: true, minute: 0), 13);
      expect(DialTimeMath.combine(hour12: 11, pm: true, minute: 0), 23);
    });

    test('非法小时读数被夹到 1~12，不会算出负点或 26 点', () {
      // 表盘不会产生 0（12 点方向给的是 12），传进来也只会被夹成 1 点
      expect(DialTimeMath.combine(hour12: 0, pm: false, minute: 0), 1);
      expect(DialTimeMath.combine(hour12: 99, pm: true, minute: 0), 12);
      // 下午 12 点就是 12:xx，不是 24:xx
      expect(DialTimeMath.combine(hour12: 99, pm: false, minute: 0), 0);
    });

    test('切上午/下午只挪 12 小时，表盘读数不变', () {
      expect(DialTimeMath.isPm(15), isTrue);
      expect(DialTimeMath.isPm(11), isFalse);
      expect(DialTimeMath.withPm(15, false), 3);
      expect(DialTimeMath.withPm(3, true), 15);
      expect(DialTimeMath.withPm(0, true), 12);
      expect(DialTimeMath.withPm(12, false), 0);
    });

    test('小时索引用 12 点方向做 0 号位', () {
      expect(DialTimeMath.hourIndexOf(12), 0);
      expect(DialTimeMath.hourIndexOf(0), 0);
      expect(DialTimeMath.hourIndexOf(1), 1);
      expect(DialTimeMath.hourIndexOf(23), 11);
    });

    test('角度与格子号互推：12 点方向为 0，顺时针每格 30 度', () {
      expect(DialTimeMath.indexFromAngle(-math.pi / 2), 0);
      expect(DialTimeMath.indexFromAngle(0), 3);
      expect(DialTimeMath.indexFromAngle(math.pi / 2), 6);
      expect(DialTimeMath.indexFromAngle(math.pi), 9);
      // 稍微偏一点时吸附到最近的格子，而不是掉到隔壁
      expect(DialTimeMath.indexFromAngle(-math.pi / 2 + 0.2), 0);
      // 逆时针偏 23 度左右（超过半格 15 度）会吸附到 11 号位
      expect(DialTimeMath.indexFromAngle(-math.pi / 2 - 0.4), 11);
    });

    test('角度生成与反推能闭环', () {
      for (var index = 0; index < 12; index++) {
        expect(DialTimeMath.indexFromAngle(DialTimeMath.angleForIndex(index)),
            index);
      }
    });
  });
}
