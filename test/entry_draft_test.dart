import 'package:bodit_app/models/entry_draft.dart';
import 'package:flutter_test/flutter_test.dart';

/// OCR 이 다 읽어낸 상태.
EntryDraft _full() => EntryDraft(
      evidencePath: '/tmp/a.jpg',
      belongDate: DateTime(2026, 8, 5),
      vendor: '영풍문고',
      description: '8월 도서',
      expenseCategory: '도서인쇄비',
      classCode: 1,
      className: '법인',
      cardLast4: '1234',
      totalAmount: 19000,
    );

void main() {
  group('isComplete / missingFields', () {
    test('다 채워지면 제출할 수 있다', () {
      expect(_full().isComplete, isTrue);
      expect(_full().missingFields, isEmpty);
    });

    test('비목이 비면 막히고 이름을 알려준다 — OCR 이 못 뽑는 항목이라 자주 걸린다', () {
      final d = _full().copyWith(expenseCategory: null);
      expect(d.isComplete, isFalse);
      expect(d.missingFields, contains('비목'));
    });

    test('여러 칸이 비면 전부 알려준다', () {
      const d = EntryDraft(evidencePath: '/tmp/a.jpg');
      expect(
        d.missingFields,
        containsAll(<String>['소속날짜', '업체명', '내역', '비목', '분류코드', '총금액']),
      );
    });
  });

  group('filename', () {
    test('항목에서 자동 생성된다', () {
      expect(_full().filename, '260805_[영풍문고]_[8월 도서]_영수증_19,000');
    });

    test('항목을 고치면 파일명도 따라 바뀐다', () {
      final d = _full().copyWith(vendor: '교보문고', totalAmount: 25000);
      expect(d.filename, '260805_[교보문고]_[8월 도서]_영수증_25,000');
    });

    test('사용자가 덮어쓰면 그 값을 쓴다', () {
      final d = _full().copyWith(filenameOverride: '내가 정한 이름');
      expect(d.filename, '내가 정한 이름');
    });

    test('사용자가 친 값에도 치환 규칙이 적용된다 — 이게 빠지면 Drive 가 깨진다', () {
      final d = _full().copyWith(filenameOverride: '260805_[A/S 비용]_영수증');
      expect(d.filename, '260805_[A-S 비용)_영수증');
      expect(d.filename, isNot(contains('/')));
    });
  });

  group('toEntry', () {
    test('비어 있으면 던지고, 무엇이 빈지 말해준다', () {
      final d = _full().copyWith(vendor: null);
      expect(
        () => d.toEntry(createdBy: 'james@bodit.co'),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', contains('업체명')),
        ),
      );
    });

    test('지출날짜를 안 고쳤으면 소속날짜를 쓴다 — 영수증에 없는 항목이다', () {
      final e = _full().toEntry(createdBy: 'james@bodit.co');
      expect(e.spendDate, e.belongDate);
    });

    test('공급가액이 안 찍혀 있으면 총액을 그대로 둔다. 1.1로 나누지 않는다', () {
      final e = _full().toEntry(createdBy: 'james@bodit.co');
      expect(e.supplyAmount, 19000);
      expect(e.vatAmount, 0);
    });

    test('해당년도·해당월은 소속날짜에서 파생된다 — 시트에 수식이 없다', () {
      final e = _full().toEntry(createdBy: 'james@bodit.co');
      expect(e.belongYear, 2026);
      expect(e.belongMonth, 8);
    });

    test('시트 행은 18칸이고 순서가 계약이다', () {
      final row = _full().toEntry(createdBy: 'james@bodit.co').toSheetRow();
      expect(row.length, 18);
      expect(row[0], 2026); //  해당년도
      expect(row[1], 8); //     해당월
      expect(row[2], '2026-08-05'); // 소속날짜
      expect(row[4], '도서인쇄비'); //  비목
      expect(row[6], '영풍문고'); //    업체명
      expect(row[8], '법인'); //        분류명 (앱이 마스터에서 찾아 채운다)
      expect(row[10], 19000); //        총금액
    });
  });
}
