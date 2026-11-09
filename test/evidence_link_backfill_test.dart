/// 나중에 올라간 Drive 링크를 **이미 들어간 시트 행**에 채우는 규칙.
///
/// 이 기능은 앱이 시트를 고치는 **유일한 길**이다(ADR Decision 2 는
/// append-only). 틀리면 남의 행에 내 증빙링크가 적히고, 시트는 되돌릴 수단이
/// 없다 — 그래서 "어느 행에 쓸지" 와 "그 행이 우리 행인지" 를 테스트로 박아둔다.
library;

import 'package:bodit_app/core/utils/retry.dart';
import 'package:bodit_app/data/remote/sheets_repository.dart';
import 'package:bodit_app/models/purchase_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// 그 행이 우리 행인지 볼 때 쓰는 두 칸(F 내역 · G 업체명)과 R(증빙링크)만
/// 채운 18칸 행. 나머지는 비교에 쓰지 않으므로 빈 칸으로 둔다.
List<Object?> sheetRow({
  String description = '8월 도서',
  String vendor = '영풍문고',
  String? evidenceUrl,
}) {
  final row = List<Object?>.filled(18, '');
  row[5] = description;
  row[6] = vendor;
  row[17] = evidenceUrl ?? '';
  return row;
}

void main() {
  group('append 가 돌려준 자리 읽기', () {
    test('탭 이름과 행 번호를 꺼낸다 — 따옴표는 그대로 들고 다닌다', () {
      // 다시 범위를 만들 때 그대로 써야 한다. 한글 탭은 따옴표가 필요하다.
      final at = SheetsRepository.parseAppendedRow("'매입내역'!A123:R123");
      expect(at?.sheet, "'매입내역'");
      expect(at?.row, 123);
    });

    test('따옴표 없는 탭 이름도 읽는다', () {
      final at = SheetsRepository.parseAppendedRow('Sheet1!A7:R7');
      expect(at?.sheet, 'Sheet1');
      expect(at?.row, 7);
    });

    test('두 줄 이상이면 거부한다 — 우리는 한 줄만 붙인다', () {
      // 모르는 모양에 쓰지 않는다. 한 줄만 붙였는데 여러 줄이 왔다면
      // 우리가 아는 append 가 아니다.
      expect(SheetsRepository.parseAppendedRow("'매입내역'!A10:R12"), isNull);
    });

    test('모양이 아니면 null', () {
      expect(SheetsRepository.parseAppendedRow('매입내역'), isNull);
      expect(SheetsRepository.parseAppendedRow(''), isNull);
      expect(SheetsRepository.parseAppendedRow("'매입내역'!A:R"), isNull);
    });
  });

  group('그 행이 여전히 우리 행인가', () {
    test('업체명·내역이 같고 증빙링크가 비어 있으면 쓴다', () {
      expect(
        SheetsRepository.isSameRow(
          sheetRow(),
          vendor: '영풍문고',
          description: '8월 도서',
        ),
        isTrue,
      );
    });

    test('증빙링크 칸이 짧아 아예 없는 행도 빈 것으로 본다', () {
      // 시트는 **끝의 빈 칸을 빼고** 돌려준다 — 링크가 비어 있으면 행이
      // 18칸보다 짧게 온다. 이걸 "채워져 있다" 로 읽으면 영원히 못 채운다.
      final short = <Object?>['', '', '', '', '', '8월 도서', '영풍문고'];
      expect(SheetsRepository.evidenceCellOf(short), '');
      expect(
        SheetsRepository.isSameRow(
          short,
          vendor: '영풍문고',
          description: '8월 도서',
        ),
        isTrue,
      );
    });

    test('행이 밀려 다른 건이 와 있으면 쓰지 않는다', () {
      // 회계 담당자가 위쪽 행을 지우면 번호가 밀린다. 밀린 줄 모르고 쓰면
      // **남의 행에 내 증빙링크를 적는다.** 그게 이 확인의 이유다.
      expect(
        SheetsRepository.isSameRow(
          sheetRow(vendor: '다른업체', description: '다른내역'),
          vendor: '영풍문고',
          description: '8월 도서',
        ),
        isFalse,
      );
    });

    test('이미 채워져 있으면 덮지 않는다', () {
      // 사람이 먼저 붙였을 수도 있다. 사람이 적은 쪽이 더 정확할 수 있으니
      // 덮지 않는다.
      expect(
        SheetsRepository.isSameRow(
          sheetRow(evidenceUrl: 'https://drive.google.com/file/d/xyz'),
          vendor: '영풍문고',
          description: '8월 도서',
        ),
        isFalse,
      );
    });

    test('업체명이 비면 비교할 것이 없으므로 거부한다', () {
      // 그 조건으로는 빈 행 아무 곳에나 맞는다 — 가장 위험한 경우다.
      expect(
        SheetsRepository.isSameRow(
          sheetRow(vendor: '', description: ''),
          vendor: '',
          description: '',
        ),
        isFalse,
      );
    });

    test('앞뒤 공백은 떨어내고 비교한다', () {
      expect(
        SheetsRepository.isSameRow(
          sheetRow(vendor: ' 영풍문고 ', description: ' 8월 도서 '),
          vendor: '영풍문고',
          description: '8월 도서',
        ),
        isTrue,
      );
    });
  });

  group('증빙링크는 18번째 컬럼이다', () {
    test('컬럼 수와 자리가 R 열 가정과 맞는다', () {
      // `SheetsRepository.evidenceColumn` 이 'R'(18번째)인 근거다.
      // 컬럼을 하나 늘리면 이 테스트가 먼저 깨진다 — 그래야 엉뚱한 칸에
      // 링크를 쓰지 않는다.
      final entry = PurchaseEntry(
        belongDate: DateTime(2026, 8, 5),
        spendDate: DateTime(2026, 8, 5),
        expenseCategory: '도서인쇄비',
        description: '8월 도서',
        vendor: '영풍문고',
        classCode: 44,
        className: '딥테크(카드)',
        cardNumber: '5531-46**-****-3927',
        totalAmount: 19000,
        supplyAmount: 19000,
        vatAmount: 0,
        createdBy: 'james@bodit.co',
        createdAt: DateTime(2026, 8, 5, 14, 30),
        evidenceUrl: 'https://drive.google.com/file/d/xyz',
      );

      final row = entry.toSheetRow();
      expect(row.length, 18, reason: '18칸 계약 — 늘리면 evidenceColumn 도 옮긴다');
      expect(row[17], 'https://drive.google.com/file/d/xyz');
      // 우리 행인지 보는 두 칸도 자리가 맞아야 한다.
      expect(row[6], '영풍문고');
      expect(row[5], '8월 도서');
      expect(SheetsRepository.evidenceColumn, 'R');
    });
  });

  group('다시 보낼 실패인지 가리기', () {
    test('연결이 끊긴 것은 다시 보낸다', () {
      // 운영에서 받은 그 실패다 — `package:http` 는 소켓 오류를
      // ClientException 으로 바꿔 던진다.
      expect(
        isTransientNetworkError(
          http.ClientException('Connection reset by peer'),
        ),
        isTrue,
      );
    });

    test('상태코드로 실패한 것은 다시 보내지 않는다', () {
      // 403 을 세 번 반복해도 답은 같다. 기다리게 하고 로그만 세 배가 된다.
      expect(isTransientNetworkError(StateError('403 권한 없음')), isFalse);
    });
  });
}
