import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import 'package:schedule_plan/core/logging/app_logger.dart';

/// 系统分享面板与文件选择（readme 模块三 3.6 / 模块六 6.3）。
abstract final class ShareService {
  /// 调用系统分享面板发送导出的文件（微信 / 邮箱等）。
  static Future<void> shareFile({
    required String path,
    String? subject,
    String? text,
  }) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(path)],
          subject: subject,
          text: text,
        ),
      );
    } catch (error, stack) {
      AppLogger.e('调用系统分享面板失败', error: error, stack: stack);
    }
  }

  /// 选择 Excel 文件并返回字节内容与文件名；用户取消时返回 null。
  static Future<PickedExcelFile?> pickExcel() async {
    try {
      final files = await FilePickerPlatform.instance.pickFiles(
        type: FileType.custom,
        allowedExtensions: <String>['xlsx', 'xls'],
      );
      if (files.isEmpty) {
        return null;
      }
      final file = files.first;
      final bytes = await file.readAsBytes();
      return PickedExcelFile(name: file.name, bytes: Uint8List.fromList(bytes));
    } catch (error, stack) {
      AppLogger.e('选择 Excel 文件失败', error: error, stack: stack);
      return null;
    }
  }
}

/// 选中的 Excel 文件。
class PickedExcelFile {
  const PickedExcelFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}
