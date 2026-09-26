/// 课表照片识别 · 引擎层（第 11 轮）。
///
/// ## 为什么不用「AI / LLM 服务商」
///
/// 用户的原话是"不需要 ai 或者 llm 提供商"。这个约束是**可以满足的**，
/// 而且效果比很多人预想的好，路线是：
///
/// **手机本机 OCR（离线文字识别）→ 本地规则解析 → 落库**
///
/// 文字识别这一步用系统能力就够了，完全离线：
///
/// | 平台 | 本机能力 | 是否离线 | 说明 |
/// |---|---|---|---|
/// | Android | Google ML Kit Text Recognition v2 | ✅ 完全离线 | 首次安装后模型内置，不联网；中文需加 `mlkit-cn` 依赖 |
/// | Android（小米 / OPPO / vivo 等国产机，可带 Google 服务） | GMS → ML Kit；无 GMS 时回落系统识别 | ✅ 完全离线 | 国行机上 GMS 常常缺失，所以**必须有回落**，不能只押 ML Kit |
/// | iOS | Apple Vision `VNRecognizeTextRequest` | ✅ 完全离线 | 系统自带，中文支持好；第 12 轮已明确"等 iOS 版本再启用" |
/// | 华为鸿蒙 HarmonyOS | **暂无可用实现** | — | 既没有 GMS 的 ML Kit，也没有 Apple Vision，需要单写一个后端（见下） |
///
/// ### 鸿蒙（HarmonyOS）要额外做什么
///
/// 用户第 12 轮明确"华为是鸿蒙系统，可能得额外标注"。鸿蒙**不等于** Android：
/// 它没有 GMS，`google_mlkit_text_recognition` 在纯血鸿蒙上拿不到模型。
/// 接入时需要：
///   1. 写一个 `HarmonyOcrRecognizer implements OcrRecognizer`，
///      内部调鸿蒙的 `@ohos.ai.ocr` / 系统 AI 能力（或 Core Vision Kit）；
///   2. 坐标同样归一化到 0~1 后返回 [OcrTextLine]，**上面的解析规则一行都不用改**；
///   3. 在 `ScheduleOcrService.setupRecognizer()` 里按平台注入。
/// 在那之前，这类设备会被 [UnavailableOcrRecognizer] 拦住，
/// 页面明确提示走 Excel 导入 / 手动排课，而不是给一串报错。
///
/// 课表是**结构化表格**，不是自由文本 —— 这对本机 OCR 是极有利的场景：
/// 字少、字大、有明确的表头（周一…周五 / 第 N 节）。识别出文字 + 包围盒之后，
/// 用 [ScheduleOcrParser] 的几何规则就能把格子还原出来，
/// **不需要任何语言模型参与**。
///
/// ## 当前工程状态（重要）
///
/// 本工程 `pubspec.yaml` **没有引入**任何 OCR 插件（`google_mlkit_text_recognition`
/// 需要 Android 最低版本 + 原生配置，且在 `flutter test` / Windows 桌面下不可用）。
/// 所以这里做成**可插拔后端**：
///
/// - [OcrRecognizer] 是抽象接口；
/// - 默认后端 [UnavailableOcrRecognizer] 会在调用时抛出 [OcrEngineUnavailable]
///   并附上清晰的替代方案文案（用户不会看到白屏或崩溃）；
/// - 要真正启用识别功能，只需：
///   1. `pubspec.yaml` 加 `google_mlkit_text_recognition`；
///   2. 新建一个实现 [OcrRecognizer] 的类，把 ML Kit 的 block 列表映射成
///      [OcrTextLine]（坐标已经是归一化的，见该类的文档）；
///   3. 在 [ScheduleOcrService.recognizer] 里用 `setupRecognizer()` 注入。
///
/// 这样做的理由：**识别引擎是可替换的，解析规则才是这个功能的护城河**。
/// 解析规则已经有 17 个单测压着（`test/unit/schedule_ocr_parser_test.dart`），
/// 换引擎不用动它们。
library;

import 'dart:typed_data';

import 'package:schedule_plan/core/logging/app_logger.dart';
import 'package:schedule_plan/data/services/schedule_ocr_parser.dart';
import 'package:schedule_plan/data/services/schedule_ocr_types.dart';

/// 识别引擎不可用（未接入 / 设备不支持 / 缺少 Google 服务）。
class OcrEngineUnavailable implements Exception {
  const OcrEngineUnavailable([this.message = '本机没有可用的文字识别引擎']);

  final String message;

  @override
  String toString() => 'OcrEngineUnavailable: $message';
}

/// 本机文字识别后端接口。
///
/// 实现方只需要把一张图变成若干行 [OcrTextLine]，**坐标必须归一化到 0~1**
/// （原点左上），因为手机照片的像素尺寸千差万别，归一化之后解析规则才与分辨率无关。
///
/// 实现要求：
/// - **不能联网**（这条是硬约束：图片不出设备）；
/// - 遇到引擎缺失应抛 [OcrEngineUnavailable]，不要静默返回空列表
///   （静默返回空会让用户以为是"照片拍得太差"）。
abstract interface class OcrRecognizer {
  /// 这个后端在当前设备上是否可用。
  Future<bool> isAvailable();

  /// 识别图中文字的每一行；坐标归一化到 0~1。
  Future<List<OcrTextLine>> recognize(Uint8List imageBytes);
}

/// 兜底后端：永远不可用，并给出可读的原因。
class UnavailableOcrRecognizer implements OcrRecognizer {
  const UnavailableOcrRecognizer([this.reason = 'ocrEngineUnavailableBody']);

  /// i18n key，UI 侧翻译后展示。
  final String reason;

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<List<OcrTextLine>> recognize(Uint8List imageBytes) async {
    throw OcrEngineUnavailable(reason);
  }
}

/// 拍照识别课表的对外的门面：**选图 → 识别 → 解析** 一条龙。
///
/// 页面只调 [recognizeToDrafts]，不关心背后是哪个引擎。
class ScheduleOcrService {
  ScheduleOcrService._();

  /// 当前注入的引擎。默认是"不可用"，接入真实引擎后调用 [setupRecognizer]。
  static OcrRecognizer _recognizer = const UnavailableOcrRecognizer();

  /// 注入本机识别引擎（见文件头"当前工程状态"）。
  static void setupRecognizer(OcrRecognizer recognizer) {
    _recognizer = recognizer;
  }

  /// 当前引擎是否可用（UI 用它决定要不要禁用入口）。
  static Future<bool> isEngineAvailable() async {
    try {
      return await _recognizer.isAvailable();
    } catch (error, stack) {
      AppLogger.e('检测本机识别引擎失败', error: error, stack: stack);
      return false;
    }
  }

  /// 识别一张课表图片并解析成结构化草稿。
  ///
  /// 抛 [OcrEngineUnavailable] 表示本机没有识别能力（调用方应展示替代方案）。
  static Future<ScheduleOcrResult> recognizeToDrafts(Uint8List imageBytes) async {
    final lines = await _recognizer.recognize(imageBytes);
    final result = ScheduleOcrParser.parse(lines);
    AppLogger.i(
      '课表识别完成：${lines.length} 行 → ${result.drafts.length} 节，'
      '信心 ${result.confidence}',
    );
    return result;
  }
}
