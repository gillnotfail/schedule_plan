/// 框选控件单测（第 11 轮）。
///
/// 这类控件最容易出的 bug 是"手指位置和框的位置对不上"——
/// 因为图片按 contain 铺进可用空间时，屏幕像素与图片比例之间差着一个缩放系数。
/// 这些用例把变换与命中判定钉住。
///
/// **注意**：测试里**不能**用真实的 `decodeImageFromList`——它在 fake async
/// 区域里永远不 resolve，会让用例挂到 10 分钟超时。所以统一注入
/// [CropSelector.imageSizeProvider] 返回一个固定尺寸。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:schedule_plan/features/management/crop_selector.dart';

/// 假的字节：真实解码不会发生（尺寸由 provider 给），只要非空即可。
final Uint8List kFakeBytes = Uint8List.fromList(<int>[1, 2, 3, 4]);

/// 4:3 的图片尺寸。
Future<Size> _fixedSize(Uint8List bytes) async => const Size(400, 300);

Future<void> _pump(
  WidgetTester tester, {
  required Rect crop,
  required ValueChanged<Rect> onChanged,
  Size viewport = const Size(400, 800),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = viewport;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 380,
            height: 600,
            child: CropSelector(
              imageBytes: kFakeBytes,
              crop: crop,
              onChanged: onChanged,
              imageSizeProvider: _fixedSize,
            ),
          ),
        ),
      ),
    ),
  );
  // 一次 microtask + 一帧，让 FutureBuilder 拿到 provider 的结果
  await tester.pump();
  await tester.pump();
}

void main() {
  group('contain 缩放系数（纯函数）', () {
    test('窄容器按宽度约束，高容器按高度约束', () {
      // 400×300 的图放进 380×600：宽 380/400=0.95，高 600/300=2.0 → 取 0.95
      expect(
        CropSelector.containScale(
          imageWidth: 400,
          imageHeight: 300,
          maxWidth: 380,
          maxHeight: 600,
        ),
        closeTo(0.95, 1e-9),
      );
      // 放进 3800×120：宽 9.5，高 0.4 → 取 0.4
      expect(
        CropSelector.containScale(
          imageWidth: 400,
          imageHeight: 300,
          maxWidth: 3800,
          maxHeight: 120,
        ),
        closeTo(0.4, 1e-9),
      );
    });

    test('非法尺寸返回 0 而不是抛异常或除零', () {
      expect(
        CropSelector.containScale(
          imageWidth: 0,
          imageHeight: 300,
          maxWidth: 380,
          maxHeight: 600,
        ),
        0,
      );
      expect(
        CropSelector.containScale(
          imageWidth: 400,
          imageHeight: 300,
          maxWidth: 0,
          maxHeight: 600,
        ),
        0,
      );
    });
  });

  testWidgets('拿到尺寸后渲染画布，不超出可用尺寸', (tester) async {
    Rect? latest;
    await _pump(
      tester,
      crop: const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9),
      onChanged: (value) => latest = value,
    );

    // 4:3 的图按 contain 铺：高比宽更宽松，所以被宽度约束住 → 高 = 宽 × 3/4
    final rect = tester.getRect(find.byType(CustomPaint).last);
    expect(rect.width, greaterThan(0));
    expect(rect.height, closeTo(rect.width * 3 / 4, 1.0));
    expect(rect.width, lessThanOrEqualTo(400));
    expect(latest, isNull, reason: '没拖动时不应该回调');
  });

  testWidgets('拖动框内区域会平移选区并保持尺寸', (tester) async {
    Rect? latest;
    await _pump(
      tester,
      crop: const Rect.fromLTRB(0.2, 0.2, 0.8, 0.8),
      onChanged: (value) => latest = value,
    );

    final rect = tester.getRect(find.byType(CustomPaint).last);
    // 选区中心：归一化 (0.5,0.5) → 画布中心
    final center = rect.center;
    // 往右拖画布宽度的 10%
    await tester.dragFrom(center, Offset(rect.width * 0.10, 0));
    await tester.pumpAndSettle();

    expect(latest, isNotNull);
    expect(
      latest!.width,
      closeTo(0.6, 0.03),
      reason: '平移不应该改变选区宽度',
    );
    expect(latest!.left, greaterThan(0.2), reason: '应该往右移动');
  });

  testWidgets('拖右下角会把选区撑大', (tester) async {
    Rect? latest;
    await _pump(
      tester,
      crop: const Rect.fromLTRB(0.2, 0.2, 0.6, 0.6),
      onChanged: (value) => latest = value,
    );

    final paintRect = tester.getRect(find.byType(CustomPaint).last);
    // 右下角在归一化 (0.6, 0.6)
    final corner = Offset(
      paintRect.left + paintRect.width * 0.6,
      paintRect.top + paintRect.height * 0.6,
    );
    await tester.dragFrom(
      corner,
      Offset(-paintRect.width * 0.1, -paintRect.height * 0.1),
    );
    await tester.pumpAndSettle();

    expect(latest, isNotNull);
    expect(latest!.right, lessThan(0.6), reason: '往左上拖应该缩小右边界');
    expect(latest!.bottom, lessThan(0.6));
    expect(latest!.left, closeTo(0.2, 0.03), reason: '左边的 x 不应动');
  });

  testWidgets('选区不会被拖出画面', (tester) async {
    Rect? latest;
    await _pump(
      tester,
      crop: const Rect.fromLTRB(0.2, 0.2, 0.8, 0.8),
      onChanged: (value) => latest = value,
    );

    final rect = tester.getRect(find.byType(CustomPaint).last);
    await tester.dragFrom(rect.center, const Offset(3000, 3000));
    await tester.pumpAndSettle();

    expect(latest, isNotNull);
    expect(latest!.left, greaterThanOrEqualTo(0.0));
    expect(latest!.top, greaterThanOrEqualTo(0.0));
    expect(latest!.right, lessThanOrEqualTo(1.0));
    expect(latest!.bottom, lessThanOrEqualTo(1.0));
    expect(latest!.width, greaterThan(0.0));
    expect(latest!.height, greaterThan(0.0));
  });

  testWidgets('尺寸还没拿到时走加载态（不崩）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CropSelector(
            imageBytes: kFakeBytes,
            crop: const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9),
            onChanged: (_) {},
            // 故意返回一个永远不完成的 Future，模拟"图片还在解码"
            imageSizeProvider: (_) => Completer<Size>().future,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
