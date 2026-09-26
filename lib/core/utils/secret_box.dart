import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// LLM API Key 的本地混淆存储（readme 3.14 表：`api_key_encrypted`）。
///
/// 说明：本实现使用 HMAC-SHA256 派生密钥流做异或混淆后再 Base64 落盘，
/// 目标是**不明文落盘**（直接打开数据库文件看不到密钥原文），
/// 强度等同于本地混淆，不能抵御针对设备的逆向工程。
abstract final class SecretBox {
  static const String _version = 'v1';

  /// 设备侧混淆因子。真实项目可改为首次启动时随机生成并写入受保护存储。
  static const String _passphrase = 'schedule_plan.local.secret';

  static const int _blockSize = 32;

  /// 加密（混淆）后返回带版本前缀的字符串。
  static String obfuscate(String plain) {
    if (plain.isEmpty) {
      return '';
    }
    final bytes = utf8.encode(plain);
    final keystream = _keystream(bytes.length);
    final output = Uint8List(bytes.length);
    for (var i = 0; i < bytes.length; i++) {
      output[i] = bytes[i] ^ keystream[i];
    }
    return '$_version:${base64Encode(output)}';
  }

  /// 还原明文。遇到未知版本或非法 Base64 时抛出 [FormatException]。
  static String reveal(String cipher) {
    if (cipher.isEmpty) {
      return '';
    }
    final separator = cipher.indexOf(':');
    if (separator <= 0) {
      throw const FormatException('密钥密文格式非法');
    }
    final version = cipher.substring(0, separator);
    if (version != _version) {
      throw FormatException('不支持的密钥密文版本: $version');
    }
    final bytes = base64Decode(cipher.substring(separator + 1));
    final keystream = _keystream(bytes.length);
    final output = Uint8List(bytes.length);
    for (var i = 0; i < bytes.length; i++) {
      output[i] = bytes[i] ^ keystream[i];
    }
    return utf8.decode(output);
  }

  /// 派生足够长度的密钥流。
  static Uint8List _keystream(int length) {
    final result = Uint8List(length);
    var block = 0;
    var offset = 0;
    while (offset < length) {
      final digest = Hmac(sha256, utf8.encode('$_passphrase|$block'))
          .convert(Uint8List(0))
          .bytes;
      for (var i = 0; i < _blockSize && offset < length; i++, offset++) {
        result[offset] = digest[i];
      }
      block++;
    }
    return result;
  }
}
