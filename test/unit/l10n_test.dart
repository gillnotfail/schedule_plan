import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _loadArb(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw TestFailure('找不到 ARB 文件：$path（请在工程根目录执行 flutter test）');
  }
  return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}

/// 过滤掉以 @ 开头的元数据键与 @@locale。
Set<String> _messageKeys(Map<String, Object?> arb) => arb.keys
    .where((key) => !key.startsWith('@'))
    .toSet();

void main() {
  final zh = _loadArb('lib/l10n/app_zh.arb');
  final en = _loadArb('lib/l10n/app_en.arb');

  group('i18n 资源一致性', () {
    test('中英文文案键完全对齐（缺失会导致运行时抛 KeyError）', () {
      final zhKeys = _messageKeys(zh);
      final enKeys = _messageKeys(en);
      expect(zhKeys.difference(enKeys), isEmpty,
          reason: '中文多出的文案键：${zhKeys.difference(enKeys)}');
      expect(enKeys.difference(zhKeys), isEmpty,
          reason: '英文多出的文案键：${enKeys.difference(zhKeys)}');
    });

    test('不存在空文案', () {
      for (final entry in <String, Map<String, Object?>>{'zh': zh, 'en': en}.entries) {
        for (final key in _messageKeys(entry.value)) {
          final value = entry.value[key];
          expect(value, isA<String>(), reason: '${entry.key}.$key 不是字符串');
          expect((value! as String).trim(), isNotEmpty,
              reason: '${entry.key}.$key 文案为空');
        }
      }
    });

    test('带占位符的文案占位符名称一致', () {
      for (final key in _messageKeys(zh)) {
        final zhMeta = zh['@$key'];
        final enMeta = en['@$key'];
        if (zhMeta == null && enMeta == null) {
          continue;
        }
        final zhPlaceholders = (zhMeta as Map<String, Object?>?)?['placeholders'];
        final enPlaceholders = (enMeta as Map<String, Object?>?)?['placeholders'];
        final zhNames = (zhPlaceholders as Map<String, Object?>?)?.keys.toSet() ?? <String>{};
        final enNames = (enPlaceholders as Map<String, Object?>?)?.keys.toSet() ?? <String>{};
        expect(zhNames, enNames, reason: '文案键 $key 的中英文占位符不一致');
      }
    });

    test('界面校验文案键齐全（禁止硬编码错误提示）', () {
      final keys = _messageKeys(zh);
      for (final key in <String>[
        'periodErrorInvalidFormat',
        'periodErrorEndBeforeStart',
        'periodErrorOverlap',
        'periodErrorNotAscending',
      ]) {
        expect(keys.contains(key), isTrue, reason: '缺少校验文案键 $key');
      }
    });
  });
}
