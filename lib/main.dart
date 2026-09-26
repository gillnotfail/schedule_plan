import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:schedule_plan/app/app_dependencies.dart';
import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 全局异常兜底：未捕获的 Flutter 框架错误也必须落日志（readme 第五章）。
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppLogger.e(
      'Flutter 框架异常：${details.exceptionAsString()}',
      error: details.exception,
      stack: details.stack,
    );
  };

  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  final dependencies = await AppDependencies.init();
  AppLogger.i('应用依赖已就绪');
  runApp(
    AppDependenciesScope(
      dependencies: dependencies,
      child: const SchedulePlanApp(),
    ),
  );
}
