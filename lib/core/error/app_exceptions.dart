/// 应用层异常基类。
///
/// readme 第五章要求：数据库写操作失败时完整回滚并向上层抛出**可读的**错误信息，
/// 因此所有异常都携带面向用户的 [message]。
class AppException implements Exception {
  const AppException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'AppException: $message${cause == null ? '' : ' ($cause)'}';
}

/// 输入校验失败（例如作息模板节次时间重叠、结束时间早于起始时间）。
class ValidationException extends AppException {
  const ValidationException(super.message, {super.cause});
}

/// 业务冲突（例如同一教师同一时间区间已排课）。
class ConflictException extends AppException {
  const ConflictException(super.message, {super.cause});
}

/// 记录不存在或外键悬空。
class NotFoundException extends AppException {
  const NotFoundException(super.message, {super.cause});
}

/// 数据库/迁移失败。
class DatabaseException extends AppException {
  const DatabaseException(super.message, {super.cause});
}
