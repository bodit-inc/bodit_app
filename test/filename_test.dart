import 'package:bodit_app/core/utils/filename.dart';
import 'package:bodit_app/models/purchase_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sanitizeSegment', () {
    test('한글·공백·언더스코어·쉼표는 그대로 통과한다', () {
      expect(sanitizeSegment('8월 도서_추가분, 2권'), '8월 도서_추가분, 2권');
    });

    test('슬래시를 바꾼다 — Drive 동기화가 깨지는 실제 케이스', () {
      expect(sanitizeSegment('A/S 비용'), 'A-S 비용');
    });

    test('파일시스템 금지문자 전부를 바꾼다', () {
      expect(sanitizeSegment(r'a<b>c:d"e/f\g|h?i*j'), 'a-b-c-d-e-f-g-h-i-j');
    });

    test('대괄호는 그대로 통과한다 — 더 이상 구분자가 아니다', () {
      // 예전엔 업체명을 `[]` 로 감싸서 닫는 괄호가 경계를 깨뜨렸다.
      // 파일명에서 값을 되파싱할 일이 없어 구분자를 없앴으므로 그냥 둔다.
      expect(sanitizeSegment('영풍문고[강남]'), '영풍문고[강남]');
    });

    test('제어문자는 버린다 (공백은 남는다)', () {
      expect(sanitizeSegment('영풍 문고'), '영풍 문고');
    });

    test('끝의 공백·마침표를 떨어낸다 — Windows 에서 문제가 된다', () {
      expect(sanitizeSegment('영풍문고. '), '영풍문고');
    });
  });

  group('formatAmountForFilename', () {
    test('천 단위 구분', () {
      expect(formatAmountForFilename(19000), '19,000');
      expect(formatAmountForFilename(800), '800');
      expect(formatAmountForFilename(1234567), '1,234,567');
    });
  });

  group('buildEvidenceFilename', () {
    test('시안·위키에 적힌 예시와 정확히 일치한다', () {
      final name = buildEvidenceFilename(
        belongDate: DateTime(2026, 8, 5),
        vendor: '영풍문고',
        description: '8월 도서',
        evidenceType: '영수증',
        amount: 19000,
      );
      expect(name, '260805_영풍문고_8월 도서_영수증_19,000');
    });

    test('값에 언더스코어가 있으면 칸 수가 늘어난다 — 감수한 것이다', () {
      // 구분자가 없으니 `_` 가 든 값은 경계를 흐린다. 그래도 괜찮은 이유:
      // 파일명을 되파싱하는 코드가 없고(증빙링크 컬럼이 그 역할을 한다),
      // 사람이 Drive 에서 눈으로 읽을 때는 짧은 쪽이 낫다.
      final name = buildEvidenceFilename(
        belongDate: DateTime(2026, 8, 5),
        vendor: 'A_B 상사',
        description: '부품_교체',
        evidenceType: '영수증',
        amount: 5000,
      );
      expect(name, '260805_A_B 상사_부품_교체_영수증_5,000');
    });
  });

  group('splitVat', () {
    test('1.1로 나눈다', () {
      final r = splitVat(11000);
      expect(r.supply, 10000);
      expect(r.vat, 1000);
    });

    test('반올림 오차가 나도 합은 항상 총액과 같다 — 회계라 1원도 어긋나면 안 된다', () {
      for (final total in [19000, 12345, 99999, 1, 7]) {
        final r = splitVat(total);
        expect(r.supply + r.vat, total, reason: 'total=$total');
      }
    });
  });

  group('stripDatePrefix — 목록은 월로 묶여 있다', () {
    test('여섯 자리 날짜 접두를 뗀다', () {
      expect(
        stripDatePrefix('260805_영풍문고_8월 도서_영수증_19,000'),
        '영풍문고_8월 도서_영수증_19,000',
      );
    });

    test('규칙을 안 따르는 이름은 그대로 둔다', () {
      // 사용자가 검토 화면에서 직접 고칠 수 있다 — 앞을 잘라내면 그 이름이
      // 사라진다.
      expect(stripDatePrefix('영풍문고 8월 도서'), '영풍문고 8월 도서');
      expect(stripDatePrefix('2608_영풍문고'), '2608_영풍문고');
      expect(stripDatePrefix('26080512_영풍문고'), '26080512_영풍문고');
      expect(stripDatePrefix('260805영풍문고'), '260805영풍문고');
      expect(stripDatePrefix(''), '');
    });

    test('날짜만 있고 뒤가 비어도 깨지지 않는다', () {
      expect(stripDatePrefix('260805_'), '');
    });
  });
}
