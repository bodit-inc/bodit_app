import 'package:bodit_app/core/utils/korean_amount.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('readKoreanAmount — 요구사항의 예시', () {
    test('1 → 일 원', () => expect(readKoreanAmount(1), '일 원'));
    test('10 → 십 원', () => expect(readKoreanAmount(10), '십 원'));
    test('100 → 백 원', () => expect(readKoreanAmount(100), '백 원'));
    test('1000 → 천 원', () => expect(readKoreanAmount(1000), '천 원'));
    test('10005 → 만 오 원', () => expect(readKoreanAmount(10005), '만 오 원'));
  });

  group('자리수 규칙', () {
    test('십·백·천 앞의 1 은 읽지 않는다', () {
      expect(readKoreanAmount(11), '십일 원');
      expect(readKoreanAmount(111), '백십일 원');
      expect(readKoreanAmount(1111), '천백십일 원');
    });

    test('만 앞의 1 은 읽지 않지만 억은 읽는다 — 우리말이 그렇다', () {
      expect(readKoreanAmount(10000), '만 원');
      expect(readKoreanAmount(100000000), '일억 원');
    });

    test('0 인 자리는 건너뛴다', () {
      expect(readKoreanAmount(10005), '만 오 원');
      expect(readKoreanAmount(100000), '십만 원');
      expect(readKoreanAmount(1000000), '백만 원');
    });

    test('네 자리씩 끊어 띄어쓴다', () {
      expect(readKoreanAmount(1234567), '백이십삼만 사천오백육십칠 원');
    });

    test('실제로 쓰일 금액들', () {
      expect(readKoreanAmount(8000), '팔천 원');
      expect(readKoreanAmount(80000), '팔만 원');
      expect(readKoreanAmount(19000), '만 구천 원');
      expect(readKoreanAmount(19800), '만 구천팔백 원');
    });

    test('0 과 음수', () {
      expect(readKoreanAmount(0), '영 원');
      expect(readKoreanAmount(-500), '마이너스 오백 원');
    });
  });

  test('formatWon — 천 단위 쉼표', () {
    expect(formatWon(0), '0');
    expect(formatWon(900), '900');
    expect(formatWon(8000), '8,000');
    expect(formatWon(1234567), '1,234,567');
  });
}
