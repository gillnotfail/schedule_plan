import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:schedule_plan/core/constants/app_constants.dart';
import 'package:schedule_plan/core/theme/app_motion.dart';

/// 课表照片的「框选区域」控件（第 11 轮）。
///
/// 为什么需要它：手机拍的课表照片里，**真正有用的只是那张表格**——
/// 周围还有桌面、手指、教室黑板、照片水印。把这些一起喂给识别引擎，
/// 会多出几十行噪声文字，直接拉低表格还原的成功率。
/// 让用户用手指框住表格，是最省事也最有效的提效手段。
///
/// 交互：
/// - 拖动四条边 / 四个角调整；
/// - 拖动框内区域整体平移；
/// - 对外只吐**归一化**的 [Rect]（0~1），因为解析层与分辨率无关。
///
/// 实现要点：图片按 `BoxFit.contain` 铺进可用空间，所以"屏幕像素"与"图片比例"
/// 之间差着一个缩放系数（[_ImageFit]），所有指针事件都要先过这个变换，
/// 否则拖动会和手指错位——这是这类控件最常见的 bug。
///
/// 为了让这个控件**可以在 `flutter test` 里测**（测试环境没有真实的图片解码），
/// 图片尺寸走 [imageSizeProvider] 注入：生产代码用 [decodeImageFromList]，
/// 测试里直接给一个常量尺寸。**不要**在测试里去 await 真实的
/// `decodeImageFromList`——它在 fake async 区域里永远不 resolve，
/// 会把用例挂到超时。
class CropSelector extends StatefulWidget {
  const CropSelector({
    super.key,
    required this.imageBytes,
    required this.crop,
    required this.onChanged,
    this.imageSizeProvider,
  });

  final Uint8List imageBytes;

  /// 归一化选区（0~1）。
  final Rect crop;

  final ValueChanged<Rect> onChanged;

  /// 图片像素尺寸的来源。默认从 [imageBytes] 解码；
  /// 测试里传一个返回固定尺寸的函数，避免依赖真实解码。
  final Future<Size> Function(Uint8List bytes)? imageSizeProvider;

  /// `BoxFit.contain` 的缩放系数（只算不画，便于单测）。
  ///
  /// 公开是为了能被单元测试直接压：这个系数算错就会让"手指拖框"整体错位，
  /// 而这种错位在真机上看起来像"控件坏了"，很难定位到一行除法。
  static double containScale({
    required double imageWidth,
    required double imageHeight,
    required double maxWidth,
    required double maxHeight,
  }) {
    if (imageWidth <= 0 || imageHeight <= 0 || maxWidth <= 0 || maxHeight <= 0) {
      return 0;
    }
    return (maxWidth / imageWidth) < (maxHeight / imageHeight)
        ? maxWidth / imageWidth
        : maxHeight / imageHeight;
  }

  @override
  State<CropSelector> createState() => _CropSelectorState();
}

/// 命中区域：边与角的可拖动热区（屏幕像素）。
const double _handleHitSize = 34.0;

/// 手柄的视觉尺寸。
const double _handleVisualSize = 18.0;

enum _DragMode { none, move, left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight }

class _CropSelectorState extends State<CropSelector> {
  _DragMode _mode = _DragMode.none;

  /// 拖动开始时的选区与起始点（屏幕像素，相对图片绘制区）。
  Rect _startRect = Rect.zero;
  Offset _startPoint = Offset.zero;

  /// 选区最小边长（占图片的比例），防止被拖成一条线。
  static const double _minSpan = 0.15;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return FutureBuilder<_ImageFit>(
          future: _resolveFit(constraints),
          builder: (context, snapshot) {
            final fit = snapshot.data;
            if (fit == null) {
              return const SizedBox(
                width: double.infinity,
                height: 240,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            // 手势区必须**严格等于**绘制区：如果让 GestureDetector 撑满
            // LayoutBuilder 给的全部空间，而 CustomPaint 只画在中间一块，
            // 手指坐标就会整体偏移（拖框和手指错位）。
            return Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanDown: (details) => _onDown(details.localPosition, fit),
                onPanUpdate: (details) => _onUpdate(details.localPosition, fit),
                onPanEnd: (_) => _onUp(),
                onPanCancel: _onUp,
                child: SizedBox(
                  width: fit.width,
                  height: fit.height,
                  child: CustomPaint(
                    painter: _CropPainter(
                      crop: widget.crop,
                      imageFit: fit,
                      scheme: Theme.of(context).colorScheme,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<_ImageFit> _resolveFit(BoxConstraints constraints) async {
    final size = await _imageSize();
    if (size.width <= 0 || size.height <= 0) {
      return const _ImageFit(width: 0, height: 0);
    }
    // 图片按 contain 放进可用空间，最长边不超过可用高度的一定比例，
    // 避免在小屏上把确认按钮顶出屏幕。
    final maxWidth = constraints.maxWidth;
    final maxHeight =
        constraints.maxHeight * AppConstants.ocrCropMaxViewFraction;
    final scale = CropSelector.containScale(
      imageWidth: size.width,
      imageHeight: size.height,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
    );
    return _ImageFit(width: size.width * scale, height: size.height * scale);
  }

  /// 取图片像素尺寸：优先用注入的来源（测试），否则真实解码。
  Future<Size> _imageSize() async {
    final provider = widget.imageSizeProvider;
    if (provider != null) {
      return provider(widget.imageBytes);
    }
    final image = await decodeImageFromList(widget.imageBytes);
    final size = Size(image.width.toDouble(), image.height.toDouble());
    image.dispose();
    return size;
  }

  void _onDown(Offset local, _ImageFit fit) {
    final rect = _toScreen(widget.crop, fit);
    _startRect = rect;
    _startPoint = local;
    _mode = _hitTest(local, rect);
    if (_mode != _DragMode.none) {
      AppMotion.select();
    }
  }

  void _onUpdate(Offset local, _ImageFit fit) {
    if (_mode == _DragMode.none) {
      return;
    }
    final delta = local - _startPoint;
    var rect = _startRect;
    switch (_mode) {
      case _DragMode.move:
        rect = rect.shift(delta);
      case _DragMode.left:
        rect = Rect.fromLTRB(rect.left + delta.dx, rect.top, rect.right, rect.bottom);
      case _DragMode.right:
        rect = Rect.fromLTRB(rect.left, rect.top, rect.right + delta.dx, rect.bottom);
      case _DragMode.top:
        rect = Rect.fromLTRB(rect.left, rect.top + delta.dy, rect.right, rect.bottom);
      case _DragMode.bottom:
        rect = Rect.fromLTRB(rect.left, rect.top, rect.right, rect.bottom + delta.dy);
      case _DragMode.topLeft:
        rect = Rect.fromLTRB(rect.left + delta.dx, rect.top + delta.dy, rect.right, rect.bottom);
      case _DragMode.topRight:
        rect = Rect.fromLTRB(rect.left, rect.top + delta.dy, rect.right + delta.dx, rect.bottom);
      case _DragMode.bottomLeft:
        rect = Rect.fromLTRB(rect.left + delta.dx, rect.top, rect.right, rect.bottom + delta.dy);
      case _DragMode.bottomRight:
        rect = Rect.fromLTRB(rect.left, rect.top, rect.right + delta.dx, rect.bottom + delta.dy);
      case _DragMode.none:
        return;
    }
    widget.onChanged(_toNormalized(_clamp(rect, fit), fit));
  }

  void _onUp() {
    _mode = _DragMode.none;
  }

  /// 保证选区不越界、不小于最小边长。
  ///
  /// 最小边长同时受两个约束：视觉上别被拖成一条线（[_minSpan]），
  /// 以及至少容得下角手柄的热区。
  Rect _clamp(Rect rect, _ImageFit fit) {
    final minPx = _handleHitSize < fit.width * _minSpan
        ? _handleHitSize
        : fit.width * _minSpan;
    final minPy = _handleHitSize < fit.height * _minSpan
        ? _handleHitSize
        : fit.height * _minSpan;
    var left = rect.left.clamp(0.0, fit.width - minPx);
    var top = rect.top.clamp(0.0, fit.height - minPy);
    var right = rect.right.clamp(left + minPx, fit.width);
    var bottom = rect.bottom.clamp(top + minPy, fit.height);
    return Rect.fromLTRB(left, top, right, bottom);
  }

  _DragMode _hitTest(Offset point, Rect rect) {
    final nearLeft = (point.dx - rect.left).abs() <= _handleHitSize;
    final nearRight = (point.dx - rect.right).abs() <= _handleHitSize;
    final nearTop = (point.dy - rect.top).abs() <= _handleHitSize;
    final nearBottom = (point.dy - rect.bottom).abs() <= _handleHitSize;
    final insideX = point.dx >= rect.left - _handleHitSize && point.dx <= rect.right + _handleHitSize;
    final insideY = point.dy >= rect.top - _handleHitSize && point.dy <= rect.bottom + _handleHitSize;

    if (nearLeft && nearTop) {
      return _DragMode.topLeft;
    }
    if (nearRight && nearTop) {
      return _DragMode.topRight;
    }
    if (nearLeft && nearBottom) {
      return _DragMode.bottomLeft;
    }
    if (nearRight && nearBottom) {
      return _DragMode.bottomRight;
    }
    if (insideX && insideY) {
      if (nearLeft) {
        return _DragMode.left;
      }
      if (nearRight) {
        return _DragMode.right;
      }
      if (nearTop) {
        return _DragMode.top;
      }
      if (nearBottom) {
        return _DragMode.bottom;
      }
      return _DragMode.move;
    }
    // 落在框外：朝最近的一条边吸附着拖（比"必须先精确点到边"友好得多）
    if (insideY && point.dx < rect.left) {
      return _DragMode.left;
    }
    if (insideY && point.dx > rect.right) {
      return _DragMode.right;
    }
    if (insideX && point.dy < rect.top) {
      return _DragMode.top;
    }
    if (insideX && point.dy > rect.bottom) {
      return _DragMode.bottom;
    }
    return _DragMode.move;
  }

  static Rect _toScreen(Rect normalized, _ImageFit fit) => Rect.fromLTRB(
        normalized.left * fit.width,
        normalized.top * fit.height,
        normalized.right * fit.width,
        normalized.bottom * fit.height,
      );

  static Rect _toNormalized(Rect screen, _ImageFit fit) => Rect.fromLTRB(
        (screen.left / fit.width).clamp(0.0, 1.0),
        (screen.top / fit.height).clamp(0.0, 1.0),
        (screen.right / fit.width).clamp(0.0, 1.0),
        (screen.bottom / fit.height).clamp(0.0, 1.0),
      );
}

class _ImageFit {
  const _ImageFit({required this.width, required this.height});

  final double width;
  final double height;
}

/// 画图：暗化框外 + 亮框 + 四角手柄 + 三分参考线。
class _CropPainter extends CustomPainter {
  const _CropPainter({
    required this.crop,
    required this.imageFit,
    required this.scheme,
  });

  final Rect crop;
  final _ImageFit imageFit;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(
      crop.left * imageFit.width,
      crop.top * imageFit.height,
      crop.right * imageFit.width,
      crop.bottom * imageFit.height,
    );

    // 框外压暗：一眼看清"哪些内容会被送进识别"
    final scrim = Paint()..color = Colors.black.withValues(alpha: 0.55);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.clipRect(rect, clipOp: ui.ClipOp.difference);
    canvas.drawRect(Offset.zero & size, scrim);
    canvas.restore();

    // 边框
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = scheme.primary;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      border,
    );

    // 三分参考线：帮用户把表格的行列对齐到框里
    final guide = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = scheme.primary.withValues(alpha: 0.35);
    for (var i = 1; i < 3; i++) {
      final dx = rect.left + rect.width * i / 3;
      final dy = rect.top + rect.height * i / 3;
      canvas.drawLine(Offset(dx, rect.top), Offset(dx, rect.bottom), guide);
      canvas.drawLine(Offset(rect.left, dy), Offset(rect.right, dy), guide);
    }

    // 四角手柄
    final handle = Paint()..color = scheme.primary;
    const half = _handleVisualSize / 2;
    for (final corner in <Offset>[
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: corner, width: _handleVisualSize, height: _handleVisualSize),
          const Radius.circular(3),
        ),
        handle,
      );
    }
    // 边中点手柄：暗示四条边也能拖
    for (final edge in <Offset>[
      Offset(rect.center.dx, rect.top),
      Offset(rect.center.dx, rect.bottom),
      Offset(rect.left, rect.center.dy),
      Offset(rect.right, rect.center.dy),
    ]) {
      canvas.drawCircle(edge, half * 0.55, handle);
    }
  }

  @override
  bool shouldRepaint(_CropPainter oldDelegate) =>
      oldDelegate.crop != crop || oldDelegate.imageFit != imageFit;
}
