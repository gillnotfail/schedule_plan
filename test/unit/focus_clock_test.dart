import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_plan/features/toolbox/focus/focus_clock.dart';

/// 起点时刻。所有用例都在这个虚拟时间轴上推演，
/// 不依赖真实时间流过，所以跑得又快又稳。
final DateTime t0 = DateTime(2026, 10, 7, 9, 0, 0);

void main() {
  group('FocusClock 墙钟计时', () {
    test('25 分钟的专注，就该老老实实走满 25 分钟', () {
      // 这条是回归测试：旧实现里 tick 是 200ms、步长却写 1 秒，
      // 25 分钟的专注 5 分钟就"完成"了。改回墙钟口径之后，
      // 「什么时候到点」只由起点与总时长决定，与刷新频率彻底解耦。
      final clock = FocusClock(total: const Duration(minutes: 25))
        ..start(t0);

      expect(clock.isFinishedAt(t0.add(const Duration(minutes: 5))), isFalse);
      expect(clock.isFinishedAt(t0.add(const Duration(minutes: 24, seconds: 59))), isFalse);
      expect(clock.isFinishedAt(t0.add(const Duration(minutes: 25))), isTrue);
      expect(
        clock.remainingAt(t0.add(const Duration(minutes: 5))),
        const Duration(minutes: 20),
      );
    });

    test('暂停期间不计时，继续之后接着算', () {
      final clock = FocusClock(total: const Duration(minutes: 30))..start(t0);

      // 专 5 分钟 → 暂停
      clock.pause(t0.add(const Duration(minutes: 5)));
      expect(clock.running, isFalse);

      // 暂停期间过了 10 分钟，一次都不该算进去
      expect(
        clock.elapsedAt(t0.add(const Duration(minutes: 15))),
        const Duration(minutes: 5),
      );

      // 15 分时继续，再坐 4 分钟 → 累计 9 分钟
      clock.resume(t0.add(const Duration(minutes: 15)));
      expect(
        clock.elapsedAt(t0.add(const Duration(minutes: 19))),
        const Duration(minutes: 9),
      );
      expect(
        clock.remainingAt(t0.add(const Duration(minutes: 19))),
        const Duration(minutes: 21),
      );
    });

    test('多次暂停继续，累计时长不受分段次数影响', () {
      final clock = FocusClock(total: const Duration(minutes: 60))..start(t0);
      var cursor = t0;

      // 坐 3 分、停 2 分，重复 4 轮 = 专注 12 分钟 / 挂钟 20 分钟
      for (var i = 0; i < 4; i++) {
        cursor = cursor.add(const Duration(minutes: 3));
        clock.pause(cursor);
        cursor = cursor.add(const Duration(minutes: 2));
        clock.resume(cursor);
      }

      expect(clock.elapsedAt(cursor), const Duration(minutes: 12));
    });

    test('剩余时间永远不会变成负数', () {
      final clock = FocusClock(total: const Duration(minutes: 1))..start(t0);

      expect(clock.remainingAt(t0.add(const Duration(hours: 5))), Duration.zero);
      expect(clock.progressAt(t0.add(const Duration(hours: 5))), 1.0);
    });

    test('重复 start / resume 不会把起点往后顶', () {
      final clock = FocusClock(total: const Duration(minutes: 10))..start(t0);
      clock.start(t0.add(const Duration(minutes: 3)));
      expect(
        clock.elapsedAt(t0.add(const Duration(minutes: 4))),
        const Duration(minutes: 4),
      );

      clock.pause(t0.add(const Duration(minutes: 4)));
      clock.resume(t0.add(const Duration(minutes: 6)));
      clock.resume(t0.add(const Duration(minutes: 7)));
      expect(
        clock.elapsedAt(t0.add(const Duration(minutes: 8))),
        const Duration(minutes: 6),
      );
    });

    test('系统时间被往回调，不吃掉已经坐过的时间', () {
      final clock = FocusClock(total: const Duration(minutes: 30))..start(t0);
      clock.pause(t0.add(const Duration(minutes: 10)));

      // 用户或 NTP 把表拨回去 1 小时，已结算的 10 分钟必须还在
      final rewound = t0.subtract(const Duration(minutes: 50));
      expect(clock.elapsedAt(rewound), const Duration(minutes: 10));
    });

    test('专注中改时长：已坐的部分不丢，只挪终点', () {
      final clock = FocusClock(total: const Duration(minutes: 25))..start(t0);
      final at = t0.add(const Duration(minutes: 10));

      clock.retotal(const Duration(minutes: 40));
      expect(clock.elapsedAt(at), const Duration(minutes: 10));
      expect(clock.remainingAt(at), const Duration(minutes: 30));

      // 往下拨到比已坐的还短 → 剩余归零，即刻算坐满
      clock.retotal(const Duration(minutes: 5));
      expect(clock.remainingAt(at), Duration.zero);
      expect(clock.isFinishedAt(at), isTrue);
    });

    test('时长钳在 1 分钟 ~ 3 小时之间', () {
      final clock = FocusClock(total: const Duration(seconds: 10));
      expect(clock.total, const Duration(minutes: 1));

      clock.retotal(const Duration(hours: 10));
      expect(clock.total, const Duration(hours: 3));
    });

    test('reset 归零后重新开始，之前的时长不留残影', () {
      final clock = FocusClock(total: const Duration(minutes: 20))..start(t0);
      clock.pause(t0.add(const Duration(minutes: 8)));

      clock.reset();
      expect(clock.elapsedAt(t0.add(const Duration(hours: 1))), Duration.zero);
      expect(clock.untouched, isTrue);

      clock.start(t0.add(const Duration(hours: 1)));
      expect(
        clock.elapsedAt(t0.add(const Duration(hours: 1, minutes: 2))),
        const Duration(minutes: 2),
      );
    });

    test('从快照还原后，时间照常往前推进', () {
      // 场景：锁屏专注到第 10 分钟时 App 被系统回收，
      // 5 分钟后用户再打开 —— 这 5 分钟人一直在坐着，不该被抹掉。
      final clock = FocusClock(total: const Duration(minutes: 25));
      clock.restore(
        total: const Duration(minutes: 25),
        settled: const Duration(minutes: 4),
        segmentStartAt: t0.add(const Duration(minutes: 6)),
      );

      expect(
        clock.elapsedAt(t0.add(const Duration(minutes: 16))),
        const Duration(minutes: 14),
      );
      expect(clock.running, isTrue);
    });

    test('还原成一个"暂停中"的快照，不会自己跑起来', () {
      final clock = FocusClock(total: const Duration(minutes: 25));
      clock.restore(
        total: const Duration(minutes: 25),
        settled: const Duration(minutes: 7),
        segmentStartAt: null,
      );

      expect(clock.running, isFalse);
      expect(clock.elapsedAt(t0.add(const Duration(days: 3))), const Duration(minutes: 7));
    });
  });

  group('专注时长格式化', () {
    test('HH:MM:SS 定宽输出', () {
      expect(formatFocusDuration(Duration.zero), '00:00:00');
      expect(formatFocusDuration(const Duration(seconds: 7)), '00:00:07');
      expect(formatFocusDuration(const Duration(minutes: 5)), '00:05:00');
      expect(
        formatFocusDuration(const Duration(hours: 2, minutes: 59, seconds: 59)),
        '02:59:59',
      );
    });

    test('负数按零处理，不吐 "-00:00:01"', () {
      expect(formatFocusDuration(const Duration(seconds: -5)), '00:00:00');
    });

    test('口语化时长：不足一分钟才说秒', () {
      expect(formatFocusSpoken(const Duration(seconds: 42)), '42 秒');
      expect(formatFocusSpoken(const Duration(minutes: 25)), '25 分钟');
      expect(
        formatFocusSpoken(const Duration(minutes: 18, seconds: 20)),
        '18 分 20 秒',
      );
    });

    test('满一小时就进位说，不写「240 分钟」', () {
      // 成果卡上的「今日累计」很容易叠到几小时，
      // 写成 240 分钟读者还得自己换算。
      expect(formatFocusSpoken(const Duration(hours: 2)), '2 小时');
      expect(
        formatFocusSpoken(const Duration(hours: 1, minutes: 20)),
        '1 小时 20 分',
      );
      expect(
        formatFocusSpoken(const Duration(hours: 1, minutes: 5, seconds: 9)),
        '1 小时 5 分 9 秒',
      );
      expect(formatFocusSpoken(const Duration(seconds: -5)), '0 秒');
    });
  });
}
