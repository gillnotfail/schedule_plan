import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:schedule_plan/core/theme/app_colors.dart';
import 'package:schedule_plan/core/theme/app_theme.dart';
import 'package:schedule_plan/data/db/schema.dart';
import 'package:schedule_plan/data/services/backup_service.dart';
import 'package:schedule_plan/features/settings/backup_page.dart';
import 'package:schedule_plan/l10n/generated/app_localizations.dart';

/// 数据备份页（用户规格第 36 轮）的交互护栏。
///
/// 三件必须成立的事：
/// - 进来默认**全选**（老师说"一键把东西都存下来"才是最常见的心愿）；
/// - 只勾「考勤记录」时，学生 / 班级 / 课程 / 课表要**自动勾上且按不动**，
///   因为它们被依赖（[BackupService.resolve]），少了恢复就失败；
/// - 点备份要落出**真文件内容**，且里面确实是选中的那几张表。

Future<Database> _openMemoryDb() {
  return databaseFactory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: DatabaseSchema.version,
      singleInstance: false,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) => DatabaseSchema.createAll(db),
    ),
  );
}

Future<void> _seed(Database db) async {
  await db.insert('class', <String, Object?>{
    'name': '高一(1)班',
    'grade': '高一',
    'color': '#4FA8F5',
    'template_id': 1,
  });
  await db.insert('student', <String, Object?>{
    'name': '张三',
    'class_id': 1,
  });
  await db.insert('course', <String, Object?>{
    'name': '数学',
    'teacher_name': '李老师',
    'class_id': 1,
  });
  await db.insert('course_class', <String, Object?>{
    'course_id': 1,
    'class_id': 1,
  });
  await db.insert('lesson', <String, Object?>{
    'course_id': 1,
    'class_id': 1,
    'teacher_id': 1,
    'weekday': 1,
    'period_index': 1,
  });
}

/// 把两个要碰平台通道的动作换掉：落盘位置、系统保存对话框。
class _FakeBackupService extends BackupService {
  _FakeBackupService({required super.database});

  String? savedContent;
  String? savedSubject;
  int saveToDeviceCalls = 0;
  Uri? saveResult = Uri.parse('content://downloads/backup.json');

  @override
  Future<String> appVersion() async => '1.0.17+18';

  @override
  Future<String> saveLocal(String content, {required String subject}) async {
    savedContent = content;
    savedSubject = subject;
    return 'C:/fake/backup.json';
  }

  @override
  Future<Uri?> saveToDevice({
    required String fileName,
    required Uint8List bytes,
    required String dialogTitle,
  }) async {
    saveToDeviceCalls++;
    return saveResult;
  }
}

void main() {
  sqfliteFfiInit();
  // 同 isolate 版：widget 测试推的是假时钟，隔离版会让 sqflite 的锁超时
  // Timer 一直挂到测试结束（与 settings_page_test 同一个理由）。
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Database db;
  late _FakeBackupService service;

  setUp(() async {
    db = await _openMemoryDb();
    service = _FakeBackupService(database: db);
  });

  tearDown(() async {
    await db.close();
  });

  void useTallWindow(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 3000);
    addTearDown(tester.view.reset);
  }

  Widget host(BackupService backup) {
    return Provider<BackupService>.value(
      value: backup,
      child: MaterialApp(
        theme: AppTheme.build(AppColorTokens.of(AppThemeKind.mint)),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: BackupPage(service: backup),
      ),
    );
  }

  /// 某一行上的复选框（含"全选"那一行）。
  Checkbox checkboxOf(WidgetTester tester, String title) {
    final row = find.widgetWithText(InkWell, title);
    return tester.widget<Checkbox>(
      find.descendant(of: row, matching: find.byType(Checkbox)),
    );
  }

  testWidgets('进来默认全选：八个复选框（含全选）都是选中的', (tester) async {
    useTallWindow(tester);
    await tester.pumpWidget(host(service));
    await tester.pumpAndSettle();

    final boxes = tester.widgetList<Checkbox>(find.byType(Checkbox)).toList();
    expect(boxes.length, 8, reason: '全选 1 行 + 7 个条目');
    expect(boxes.every((box) => box.value == true), isTrue);
  });

  testWidgets('取消全选后按钮变灰，一项都不备份', (tester) async {
    useTallWindow(tester);
    await tester.pumpWidget(host(service));
    await tester.pumpAndSettle();

    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();

    final boxes = tester.widgetList<Checkbox>(find.byType(Checkbox)).toList();
    expect(boxes.any((box) => box.value == true), isFalse);

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull, reason: '一项都没选时不能点');
  });

  testWidgets('只勾考勤：依赖项自动勾上且按不动', (tester) async {
    useTallWindow(tester);
    await tester.pumpWidget(host(service));
    await tester.pumpAndSettle();

    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('考勤记录'));
    await tester.pumpAndSettle();

    final attendance = checkboxOf(tester, '考勤记录');
    expect(attendance.value, isTrue);
    expect(attendance.onChanged, isNotNull, reason: '自己勾的能再取消');

    for (final title in <String>['学生名单', '班级名单', '课程', '课表']) {
      final box = checkboxOf(tester, title);
      expect(box.value, isTrue, reason: '$title 是考勤的依赖，必须一起备份');
      expect(box.onChanged, isNull, reason: '$title 由上面的选择决定，不能单独点掉');
    }

    expect(
      checkboxOf(tester, '偏好设置').value,
      isFalse,
      reason: '偏好设置与考勤无关，不该被拖进来',
    );
  });

  testWidgets('点备份会落出文件，内容含选中的表', (tester) async {
    useTallWindow(tester);
    await _seed(db);
    await tester.pumpWidget(host(service));
    await tester.pumpAndSettle();

    await tester.tap(find.text('备份到本机文件'));
    await tester.pumpAndSettle();

    expect(service.saveToDeviceCalls, 1);
    expect(service.savedContent, isNotNull);
    expect(service.savedSubject, '全部数据');

    final bundle = service.decode(service.savedContent!);
    expect(bundle.countOf('student'), 1);
    expect(bundle.countOf('attendance_record'), 0, reason: '还没点过名');
    expect(bundle.slices, BackupSlice.values);
  });

  testWidgets('没数据时不出文件，只提示', (tester) async {
    useTallWindow(tester);
    await tester.pumpWidget(host(service));
    await tester.pumpAndSettle();

    await tester.tap(find.text('备份到本机文件'));
    await tester.pumpAndSettle();

    expect(service.saveToDeviceCalls, 0);
    expect(service.savedContent, isNull);
    expect(find.text('选中的内容里还没有数据，先录入再来备份'), findsOneWidget);
  });
}
