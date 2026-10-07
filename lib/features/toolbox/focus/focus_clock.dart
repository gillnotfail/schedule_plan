import 'package:schedule_plan/core/constants/app_constants.dart';

/// 专注计时内核：只做减法，不碰 UI、不碰数据库、不持有定时器。
///
/// **为什么不用「每 tick 减一秒」**：那条路上"剩余时间"是一个**累加器**，
/// 定时器每一次抖动、掉帧、被系统延后，误差都会永久沉淀下来，再也补不回。
/// 而且刷新间隔与步长一旦不一致就会整体跑偏 —— 旧实现 tick 是 200ms、
/// 步长却写 1 秒，25 分钟的专注 5 分钟就"完成"了，用户看到的倒计时
/// 比真实时间快 5 倍。
///
/// 这里换成**墙钟口径**：
/// - 只记「已经结算掉的时长」与「当前这一段的起点」；
/// - 剩余时间 = 总时长 −（已结算 + 当前段），每次用传进来的 `now` 现算。
///
/// 于是掉帧只是"少画几帧"，时间永远对得上；暂停也不过是在结算点上切一刀。
/// 所有方法都接收显式的 `now`（而不是内部 `DateTime.now()`），
/// 这样单测可以喂任意时间轴，不用等真实时间流过，也不用 fake async。
class FocusClock {
  FocusClock({required Duration total}) : _total = _clampTotal(total);

  Duration _total;

  /// 已经结算掉的专注时长（此前每一段的和）。
  Duration _settled = Duration.zero;

  /// 当前这一段的起点；为 null 表示没在跑（未开始或已暂停）。
  DateTime? _segmentStart;

  /// 当前这一段的起点；为 null 表示没在跑（未开始或已暂停）。
  DateTime? get segmentStart => _segmentStart;

  /// 计划时长，永远落在 [AppConstants.focusMinSeconds] ~
  /// [AppConstants.focusMaxSeconds] 之间。
  Duration get total => _total;

  /// 正在计时（未暂停）。
  bool get running => _segmentStart != null;

  /// 是否还没开始过（用于区分"准备态"与"暂停态"）。
  bool get untouched => _settled == Duration.zero && _segmentStart == null;

  /// 已专注时长，把正在跑的这一段也算进去。
  Duration elapsedAt(DateTime now) {
    final start = _segmentStart;
    if (start == null) {
      return _settled;
    }
    final live = now.difference(start);
    // 系统时间被往回调（用户改时间、NTP 校正）时 difference 会是负数，
    // 不让它把已结算的时长吃掉。
    return _settled + (live.isNegative ? Duration.zero : live);
  }

  /// 剩余时长，永不小于零。
  Duration remainingAt(DateTime now) {
    final left = _total - elapsedAt(now);
    return left.isNegative ? Duration.zero : left;
  }

  /// 完成度 0.0 ~ 1.0。
  double progressAt(DateTime now) {
    final totalMs = _total.inMilliseconds;
    if (totalMs <= 0) {
      return 1;
    }
    return (elapsedAt(now).inMilliseconds / totalMs).clamp(0.0, 1.0);
  }

  /// 是否已经坐满了。
  bool isFinishedAt(DateTime now) => elapsedAt(now) >= _total;

  /// 开始。重复调用无副作用（`_segmentStart` 只认第一次）。
  void start(DateTime now) => _segmentStart ??= now;

  /// 暂停：把当前这一段结进 [_settled]，起点清空。
  void pause(DateTime now) {
    if (_segmentStart == null) {
      return;
    }
    _settled = elapsedAt(now);
    _segmentStart = null;
  }

  /// 从暂停中继续（语义上就是再开一段）。
  void resume(DateTime now) => _segmentStart ??= now;

  /// 改计划时长（长按屏幕上下拨）。
  ///
  /// 已专注的部分**不动**，只挪终点：从 25 分钟拨到 40 分钟，
  /// 已经坐的 10 分钟还在，剩余从 15 变成 30。
  /// 往下拨到比已专注还短时，剩余归零 → 立刻算作坐满（这是合理结果）。
  void retotal(Duration next) => _total = _clampTotal(next);

  /// 归零重来（双击屏幕）。
  void reset({Duration? total}) {
    _settled = Duration.zero;
    _segmentStart = null;
    if (total != null) {
      _total = _clampTotal(total);
    }
  }

  /// 从快照还原。
  ///
  /// `segmentStartAt` 传 null 表示快照记的是"暂停中"。
  /// 注意还原后**不补偿**关机那段时间之外的东西 —— 起点是真实的墙钟时刻，
  /// 所以 App 被杀掉又打开时，时间照常推进（那段时间人确实在专注），
  /// 若期间已经到点，[isFinishedAt] 会直接为真。
  void restore({
    required Duration total,
    required Duration settled,
    required DateTime? segmentStartAt,
  }) {
    _total = _clampTotal(total);
    _settled = settled.isNegative ? Duration.zero : settled;
    _segmentStart = segmentStartAt;
  }

  static Duration _clampTotal(Duration value) {
    final seconds = value.inSeconds;
    if (seconds < AppConstants.focusMinSeconds) {
      return const Duration(seconds: AppConstants.focusMinSeconds);
    }
    if (seconds > AppConstants.focusMaxSeconds) {
      return const Duration(seconds: AppConstants.focusMaxSeconds);
    }
    return Duration(seconds: seconds);
  }
}

/// 把秒数格式化成 `HH:MM:SS`（用户规格里的 `00:00:00`）。
///
/// 超过 99 小时也照样按两位小时显示（不会变成 `100:00:00` 撑破布局）——
/// 本应用上限 3 小时，这只是防呆。
String formatFocusDuration(Duration duration) {
  final totalSeconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  final hh = hours.toString().padLeft(2, '0');
  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');
  return '$hh:$mm:$ss';
}

/// 「18 分 20 秒」这种口语化时长，用在退出拦截与成果卡上。
///
/// 只到分钟时省掉秒（「已专注 25 分钟」），不足一分钟才说秒 ——
/// 「已专注 0 分钟」读起来像嘲讽。
///
/// 超过一小时要进位说「1 小时 20 分」：成果卡上的「今日累计」很容易
/// 叠到几小时，写成「240 分钟」读者还得自己换算。
String formatFocusSpoken(Duration duration) {
  final totalSeconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
  if (totalSeconds < 60) {
    return '$totalSeconds 秒';
  }
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    if (seconds > 0) {
      return '$hours 小时 $minutes 分 $seconds 秒';
    }
    if (minutes > 0) {
      return '$hours 小时 $minutes 分';
    }
    return '$hours 小时';
  }
  if (seconds == 0) {
    return '$minutes 分钟';
  }
  return '$minutes 分 $seconds 秒';
}
