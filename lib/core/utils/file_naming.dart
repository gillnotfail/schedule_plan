/// 导出文件的命名口径（用户规格第 35 轮）。
///
/// 统一成 `导出时间-对象-内容.xlsx`：
/// - 课程维度：`20261112-2038-数学-出勤情况.xlsx`
/// - 学生维度：`20261112-2038-张三-出勤记录.xlsx`
///
/// 时间放在最前面，是因为老师导出后基本都堆在同一个文件夹里，
/// 按名字排序 = 按导出时间排序；接着是"给谁导的"，最后才是"导的什么"，
/// 一眼能分出是哪个学生、哪门课，不用逐个点开看。
library;

/// 导出时间戳：`20261112-2038`（本地时间，精确到分钟）。
///
/// 不用 `:` / `/`：Windows 文件名不允许，安卓分享出去也会被改名。
String exportStamp([DateTime? now]) {
  final time = now ?? DateTime.now();
  final year = time.year.toString().padLeft(4, '0');
  final month = time.month.toString().padLeft(2, '0');
  final day = time.day.toString().padLeft(2, '0');
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$year$month$day-$hour$minute';
}

/// 文件名里不能出现的字符（Windows 最严，安卓次之，统一按最严的来）。
final RegExp _illegal = RegExp(r'[\\/:*?"<>|\x00-\x1F]');

/// 把用户可见的名称（课程名、学生名）清理成能落盘的片段。
///
/// 课程名里出现 `/`（"数学/物理"）、学生名里带空格都很常见，
/// 直接拼进路径会建出子目录或让分享面板报错，所以一律替换成 `-`。
String sanitizeFilePart(String raw, {int maxLength = 40}) {
  var value = raw.replaceAll(_illegal, '-');
  // 连续分隔符压成一个，免得出现 `数学---出勤情况`
  value = value.replaceAll(RegExp(r'-{2,}'), '-');
  value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  // 替换字符留下的 `- `（"3班: 周二" → "3班- 周二"）收成 `-`
  value = value.replaceAll(RegExp(r'\s*-\s*'), '-');
  // 首尾的点和横线在 Windows 上会被吞掉或导致隐藏文件
  value = value.replaceAll(RegExp(r'^[-.\s]+|[-.\s]+$'), '');
  if (value.length > maxLength) {
    value = value.substring(0, maxLength).trim();
    value = value.replaceAll(RegExp(r'[-.\s]+$'), '');
  }
  return value;
}

/// 拼装导出文件名：`{时间}-{对象}-{内容}.{扩展名}`。
///
/// [subject] 为空时（比如没筛课程、也没指定学生）只输出 `{时间}-{内容}`，
/// 不会留下一个空的双横线。
String buildExportFileName({
  required String kind,
  String? subject,
  String extension = 'xlsx',
  DateTime? now,
}) {
  final parts = <String>[
    exportStamp(now),
    if (subject != null && sanitizeFilePart(subject).isNotEmpty)
      sanitizeFilePart(subject),
    sanitizeFilePart(kind),
  ];
  return '${parts.join('-')}.$extension';
}
