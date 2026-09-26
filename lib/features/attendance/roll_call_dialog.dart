import 'dart:math';

import 'package:flutter/material.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/l10n/l10n_extensions.dart';
import 'package:schedule_plan/data/models/student.dart';

/// 随机点名「老虎机滚动」动画（模块二 2.8）。
///
/// - 姓名列表快速滚动后逐渐减速，最终定格在随机选中的学生上
/// - 减速曲线 easeOutCubic，总时长约 2.5 秒
/// - 已点过名的学生本次点名会话内不重复抽取，直到全部点完一轮后重置
Future<Student?> showRollCallDialog(
  BuildContext context,
  List<Student> students,
) {
  if (students.isEmpty) {
    return Future<Student?>.value(null);
  }
  return showDialog<Student>(
    context: context,
    builder: (_) => _RollCallDialog(students: students),
  );
}

class _RollCallDialog extends StatefulWidget {
  const _RollCallDialog({required this.students});

  final List<Student> students;

  @override
  State<_RollCallDialog> createState() => _RollCallDialogState();
}

class _RollCallDialogState extends State<_RollCallDialog>
    with SingleTickerProviderStateMixin {
  /// 会话级已点名单（静态）：全部点完一轮后自动重置。
  static final Set<int> _sessionPicked = <int>{};

  late final AnimationController _controller;
  late final int _targetIndex;
  static const double _itemHeight = 56.0;

  @override
  void initState() {
    super.initState();
    final available = widget.students
        .where((item) => !_sessionPicked.contains(item.id))
        .toList();
    final pool = available.isEmpty ? widget.students : available;
    if (available.isEmpty) {
      _sessionPicked.clear();
    }
    _targetIndex = widget.students.indexOf(pool[Random().nextInt(pool.length)]);
    _controller = AnimationController(
      vsync: this,
      duration: AppConstants.rollCallDuration,
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish() {
    final student = widget.students[_targetIndex];
    if (student.id != null) {
      _sessionPicked.add(student.id!);
      if (_sessionPicked.length >= widget.students.length) {
        _sessionPicked.clear();
      }
    }
    Navigator.of(context).pop(student);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final total = widget.students.length;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final eased = Curves.easeOutCubic.transform(_controller.value);
        final cycles = 8;
        final position = (eased * cycles * total + _targetIndex) % total;
        return AlertDialog(
          title: Text(_controller.isCompleted ? '' : l10n.rollCallTitle),
          content: SizedBox(
            height: _itemHeight,
            child: ClipRect(
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  for (var i = 0; i < total; i++)
                    Transform.translate(
                      offset: Offset(
                        0,
                        ((i - position + total) % total) * _itemHeight -
                            (total ~/ 2) * _itemHeight,
                      ),
                      child: SizedBox(
                        height: _itemHeight,
                        child: Center(
                          child: Text(
                            widget.students[i].name,
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.close),
            ),
            if (_controller.isCompleted)
              FilledButton(onPressed: _finish, child: Text(l10n.ok)),
          ],
        );
      },
    );
  }
}
