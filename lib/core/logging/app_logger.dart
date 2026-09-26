import 'dart:developer' as developer;

/// 统一日志门面。
///
/// readme 第五章「错误处理」强制要求：严禁空 catch 块吞异常，
/// 任何 catch 块必须至少记录日志。所有 catch 一律调用 [AppLogger.e]。
abstract final class AppLogger {
  static const String _name = 'schedule_plan';

  static void d(String message) => _write(500, 'D', message);

  static void i(String message) => _write(800, 'I', message);

  static void w(String message) => _write(900, 'W', message);

  /// 记录异常。所有 catch 块必须调用本方法，禁止空实现。
  static void e(String message, {Object? error, StackTrace? stack}) =>
      _write(1000, 'E', message, error: error, stack: stack);

  static void _write(
    int level,
    String tag,
    String message, {
    Object? error,
    StackTrace? stack,
  }) {
    developer.log(
      '[$tag] $message',
      name: _name,
      level: level,
      error: error,
      stackTrace: stack,
    );
  }
}
