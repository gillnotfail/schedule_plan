import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/core/widgets/app_card.dart';
import 'package:schedule_plan/core/widgets/app_snackbar.dart';
import 'package:schedule_plan/data/models/schedule_event.dart';
import 'package:schedule_plan/data/repositories/note_repository.dart';
import 'package:schedule_plan/data/settings_state.dart';

/// 专注模式（番茄钟，模块五 5.1）。
///
/// 圆形进度条内部有水波纹随进度上涨的视觉效果。
class FocusTimerPage extends StatefulWidget {
  const FocusTimerPage({super.key});

  @override
  State<FocusTimerPage> createState() => _FocusTimerPageState();
}

class _FocusTimerPageState extends State<FocusTimerPage>
    with SingleTickerProviderStateMixin {
  Timer? _ticker;
  late AnimationController _wave;
  bool _running = false;
  bool _isBreak = false;
  int _remainingSeconds = 0;
  int _totalSeconds = 0;

  @override
  void initState() {
    super.initState();
    _wave = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _reset(isBreak: false);
  }

  @override
  void dispose() {
    // readme 第六章：Timer / 动画控制器必须显式释放
    _ticker?.cancel();
    _ticker = null;
    _wave.dispose();
    super.dispose();
  }

  void _reset({required bool isBreak}) {
    final settings = context.read<SettingsState>();
    final minutes = isBreak ? settings.focusBreakMinutes : settings.focusMinutes;
    setState(() {
      _isBreak = isBreak;
      _totalSeconds = minutes * 60;
      _remainingSeconds = minutes * 60;
      _running = false;
    });
  }

  void _start() {
    _ticker?.cancel();
    setState(() => _running = true);
    _ticker = Timer.periodic(AppConstants.focusTicker, (_) {
      if (_remainingSeconds <= 0) {
        _finish();
        return;
      }
      setState(() => _remainingSeconds -= 1);
    });
  }

  void _pause() {
    _ticker?.cancel();
    _ticker = null;
    setState(() => _running = false);
  }

  Future<void> _finish() async {
    _ticker?.cancel();
    _ticker = null;
    setState(() => _running = false);
    try {
      await context.read<ScheduleEventRepository>().saveFocusSession(
            FocusSession(
              startedAt: DateTime.now().millisecondsSinceEpoch,
              durationMinutes: _totalSeconds ~/ 60,
              completed: true,
            ),
          );
    } catch (error, stack) {
      AppLogger.e('保存专注记录失败', error: error, stack: stack);
    }
    if (!mounted) {
      return;
    }
    showAppSnackBar(context, context.l10n.focusDone);
    _reset(isBreak: !_isBreak);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final progress = _totalSeconds == 0
        ? 0.0
        : (_totalSeconds - _remainingSeconds) / _totalSeconds;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.focusTimer)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: 220,
              height: 220,
              child: AnimatedBuilder(
                animation: _wave,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _WaterRipplePainter(
                      progress: progress,
                      wavePhase: _wave.value,
                      color: theme.colorScheme.primary,
                      trackColor: theme.colorScheme.surfaceContainerHighest,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: AppConstants.spaceL),
            Text(
              _format(_remainingSeconds),
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: AppConstants.spaceS),
            Text(_isBreak ? l10n.focusBreak : l10n.focusTimer),
            const SizedBox(height: AppConstants.spaceL),
            AppCard(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spaceL,
                vertical: AppConstants.spaceS,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  IconButton(
                    icon: Icon(_running ? Icons.pause : Icons.play_arrow),
                    onPressed: _running ? _pause : _start,
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () => _reset(isBreak: _isBreak),
                  ),
                  TextButton(
                    onPressed: () => _reset(isBreak: !_isBreak),
                    child: Text(_isBreak ? l10n.focusTimer : l10n.focusBreak),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _format(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// 圆形进度 + 内部水波纹。
class _WaterRipplePainter extends CustomPainter {
  const _WaterRipplePainter({
    required this.progress,
    required this.wavePhase,
    required this.color,
    required this.trackColor,
  });

  final double progress;
  final double wavePhase;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outer = size.width / 2 - 6;
    final inner = outer - 16;

    canvas.drawCircle(
      center,
      outer,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..color = trackColor,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: outer),
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..color = color,
    );

    // 内部水波纹：水位随进度上涨
    final waterLevel = center.dy + inner - 2 * inner * progress.clamp(0.0, 1.0);
    final clip = Path()
      ..addOval(Rect.fromCircle(center: center, radius: inner));
    canvas.save();
    canvas.clipPath(clip);
    final wave = Path()
      ..moveTo(center.dx - inner, waterLevel);
    for (var x = -inner; x <= inner; x += 4) {
      final y = waterLevel +
          6 * math.sin((x / 28) + wavePhase * 2 * math.pi);
      wave.lineTo(center.dx + x, y);
    }
    wave
      ..lineTo(center.dx + inner, center.dy + inner)
      ..lineTo(center.dx - inner, center.dy + inner)
      ..close();
    canvas.drawPath(wave, Paint()..color = color.withValues(alpha: 0.35));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WaterRipplePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.wavePhase != wavePhase ||
      oldDelegate.color != color;
}
