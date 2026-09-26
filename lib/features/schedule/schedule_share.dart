import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:schedule_plan/core/logging/app_logger.dart';

/// 课表分享：把**当前显示的课表**截图，底部拼上「app 名 + 二维码位」信息带，
/// 再存进系统相册 / 唤起系统分享面板。
///
/// 用户规格（第 8 轮）："课表页右上角……新增一个分享按钮。当用户点击该按钮，
/// 自动截图当前课表的屏幕，同时在课表最下方加上 app 名。……
/// 因为涉及到两个课表，错峰课表和常规课表，所以以当前页面显示的为准。
/// 支持用户将截图保存到相册，如果需要权限，记的提醒。"
///
/// 「以当前页面显示的为准」是靠截图**屏幕上真实渲染的那一块**实现的
/// （课表页把正文包在 `RepaintBoundary(_captureBodyKey)` 里），
/// 不另起一套"分享专用"的渲染 —— 错峰 / 常规、缩放比例、今天的列高亮全都一致。
///
/// 底部信息带是另一块离屏的 `RepaintBoundary`（[_footerKey] 说明见
/// `ScheduleShareFooter`），截图后按宽度等比拼接到课表图下方。
///
/// 权限口径：
/// - Android 10+（API 29+，分区存储）保存相册**不需要任何权限**；
/// - Android 9-（本项目 minSdk 26）需要 `WRITE_EXTERNAL_STORAGE` 运行时权限，
///   `Gal.putImageBytes` 会自动申请；被拒绝时页面侧提示并给「去设置」。
class ScheduleShare {
  ScheduleShare._();

  /// 导出倍率：3x 足够打印和放大看，再高只换来更大的文件。
  static const double pixelRatio = 3.0;

  /// 截图并拼上底部信息带。任一块还没准备好（没布局完 / 尺寸为 0）返回 null。
  static Future<Uint8List?> capture({
    required GlobalKey bodyKey,
    required GlobalKey footerKey,
  }) async {
    final body = await _snap(bodyKey);
    if (body == null) {
      return null;
    }
    final footer = await _snap(footerKey);
    if (footer == null) {
      return null;
    }
    try {
      final merged = await _stackVertical(body, footer);
      final data = await merged.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } catch (error, stack) {
      AppLogger.e('课表截图失败', error: error, stack: stack);
      return null;
    }
  }

  /// 存进系统相册（根目录，不另建相册 —— 建相册在 Android 10+ 要额外授权）。
  ///
  /// 内部会自动申请权限；被拒绝抛 [GalException]（`accessDenied`）。
  static Future<void> saveToGallery(Uint8List bytes) =>
      Gal.putImageBytes(bytes);

  /// 唤起系统分享面板（分享不需要存储权限，可作为"没给相册权限"时的兜底出口）。
  static Future<void> openShareSheet(Uint8List bytes, {String? text}) async {
    final path = await writeToTemp(bytes);
    // share_plus 13.x：静态 Share.* 已弃用，统一走 SharePlus.instance
    await SharePlus.instance.share(
      ShareParams(files: <XFile>[XFile(path)], text: text),
    );
  }

  static Future<String> writeToTemp(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final name =
        'schedule_${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
    final file = File('${dir.path}/$name.png');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static Future<ui.Image?> _snap(GlobalKey key) async {
    final context = key.currentContext;
    final obj = context?.findRenderObject();
    if (obj is! RenderRepaintBoundary) {
      return null;
    }
    if (!obj.hasSize || obj.size.isEmpty) {
      return null;
    }
    return obj.toImage(pixelRatio: pixelRatio);
  }

  /// 上下拼接：底部按课表宽度等比缩放（两边逻辑宽度一致时就是原样拼接）。
  static Future<ui.Image> _stackVertical(ui.Image top, ui.Image bottom) {
    final width = top.width.toDouble();
    final scale = width / bottom.width.toDouble();
    final bottomHeight = bottom.height * scale;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImage(top, ui.Offset.zero, ui.Paint());
    canvas.drawImageRect(
      bottom,
      ui.Rect.fromLTWH(
        0,
        0,
        bottom.width.toDouble(),
        bottom.height.toDouble(),
      ),
      ui.Rect.fromLTWH(0, top.height.toDouble(), width, bottomHeight),
      ui.Paint(),
    );
    return recorder
        .endRecording()
        .toImage(top.width, (top.height + bottomHeight).round());
  }
}
