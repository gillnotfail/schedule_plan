import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_plan/core/utils/secret_box.dart';

void main() {
  group('SecretBox', () {
    test('往返加解密还原原文', () {
      const plain = 'sk-abcdef1234567890';
      final cipher = SecretBox.obfuscate(plain);
      expect(cipher, isNot(plain));
      expect(SecretBox.reveal(cipher), plain);
    });

    test('密文不以明文形式落盘（数据库文件里看不到原文）', () {
      final cipher = SecretBox.obfuscate('sk-live-9876543210');
      expect(cipher.contains('sk-live-9876543210'), isFalse);
    });

    test('空字符串按空处理', () {
      expect(SecretBox.obfuscate(''), '');
      expect(SecretBox.reveal(''), '');
    });

    test('中文与超长密钥均可往返', () {
      final long = '密钥' * 200;
      expect(SecretBox.reveal(SecretBox.obfuscate(long)), long);
    });

    test('相同明文产生相同密文（便于去重与比较）', () {
      expect(SecretBox.obfuscate('abc'), SecretBox.obfuscate('abc'));
    });

    test('缺少版本前缀 → FormatException', () {
      expect(() => SecretBox.reveal('abcdef'), throwsA(isA<FormatException>()));
    });

    test('未知版本 → FormatException', () {
      expect(() => SecretBox.reveal('v99:abcd'), throwsA(isA<FormatException>()));
    });
  });
}
