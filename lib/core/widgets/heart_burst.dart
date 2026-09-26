import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 点击背景/卡片时**爆散爱心**的粒子层（给教师情绪价值）。
///
/// 用户规格（第 9 轮）："第二页是教学成果展示……当用户点击背景或者这页卡片时，
/// 背景可以点击爆散爱心，心形，0.7-1.28-3.6，颗粒子晚 0.1s 起步。给用户提供情绪价值。"
///
/// 实现要点：
/// - 在 [child] 之上铺一层 `IgnorePointer` 的 `CustomPaint`，点到哪儿从哪儿爆一簇心；
/// - 心形从 0.7 倍起**边上升边放大**（约长到 1.3 倍）、并淡出，模拟"绽开"；
/// - 每颗粒子**晚 0.1s 起步**（另加随机抖动），错开成一串而不是同时冒出来；
/// - 心形用字形 '❤' 绘制，颜色在一组红/粉/珊瑚色里轮转。
class HeartBurst extends StatefulWidget {
  const HeartBurst({super.key, required this.child});

  final Widget child;

  @override
  State<HeartBurst> createState() => _HeartBurstState();
}

class _HeartBurstState extends State<HeartBurst>
    with SingleTickerProviderStateMixin {
  final Stopwatch _clock = Stopwatch();
  final List<_Heart> _hearts = <_Heart>[];
  late final Ticker _ticker = Ticker(_onTick);

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration _) {
    if (!mounted) {
      return;
    }
    if (_hearts.isEmpty) {
      _ticker.stop();
      _clock.stop();
      return;
    }
    setState(() {});
  }

  void _burst(Offset at) {
    if (!_clock.isRunning) {
      _clock
        ..reset()
        ..start();
    }
    final rnd = math.Random();
    const colors = <Color>[
      Color(0xFFE5396E),
      Color(0xFFFF6B81),
      Color(0xFFFF8A80),
      Color(0xFFF06292),
    ];
    for (var i = 0; i < 12; i++) {
      // 向上为主的扇形，让心形"绽开"而非四散
      final angle = (math.pi / 2) + (rnd.nextDouble() - 0.5) * math.pi * 0.85;
      final speed = 140 + rnd.nextDouble() * 180;
      _hearts.add(
        _Heart(
          origin: at,
          vx: math.cos(angle) * speed,
          vy: math.sin(angle) * speed,
          size: 10 + rnd.nextDouble() * 16,
          delay: 0.1 + rnd.nextDouble() * 0.18,
          life: 1.1 + rnd.nextDouble() * 0.6,
          color: colors[rnd.nextInt(colors.length)],
        ),
      );
    }
    if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (details) => _burst(details.localPosition),
      child: Stack(
        children: <Widget>[
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _HeartPainter(
                  hearts: _hearts,
                  now: _clock.elapsedMilliseconds / 1000.0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Heart {
  _Heart({
    required this.origin,
    required this.vx,
    required this.vy,
    required this.size,
    required this.delay,
    required this.life,
    required this.color,
  });

  final Offset origin;
  final double vx;
  final double vy;
  final double size;
  final double delay;
  final double life;
  final Color color;
}

class _HeartPainter extends CustomPainter {
  _HeartPainter({required this.hearts, required this.now});

  final List<_Heart> hearts;
  final double now;

  /// 向上减速的"重力"：心形先上飘，再慢慢回落
  static const double _gravity = 220.0;

  @override
  void paint(Canvas canvas, Size size) {
    final alive = <_Heart>[];
    for (final h in hearts) {
      final age = now - h.delay;
      if (age < 0 || age > h.life) {
        continue;
      }
      alive.add(h);
      final t = age / h.life;
      final x = h.origin.dx + h.vx * age;
      final y = h.origin.dy + h.vy * age + 0.5 * _gravity * age * age;
      final opacity = (1 - t).clamp(0.0, 1.0);
      final scale = 0.7 + 0.6 * t; // 0.7 起步，绽开到 ~1.3
      final fontSize = h.size * scale;
      final tp = TextPainter(
        text: TextSpan(
          text: '❤',
          style: TextStyle(
            fontSize: fontSize,
            color: h.color.withValues(alpha: opacity),
            height: 1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - fontSize / 2, y - fontSize / 2));
    }
    hearts
      ..clear()
      ..addAll(alive);
  }

  @override
  bool shouldRepaint(covariant _HeartPainter oldDelegate) => true;
}
