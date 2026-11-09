/// 카드번호 칸이 **뒤 4자리에서 전체 번호로** 바뀐 것을 지킨다.
///
/// 시트는 append-only 라 잘못 들어간 값을 앱으로 못 지운다. 그래서 두 가지를
/// 테스트로 못 박는다 — 시트에 들어가는 자리(10번 컬럼)와, 앱을 올릴 때
/// **기기에 남아 있던 전송 대기 건**이 되살아나는지.
library;

import 'package:bodit_app/models/purchase_entry.dart';
import 'package:flutter_test/flutter_test.dart';

PurchaseEntry _entry({String cardNumber = '5531-46**-****-3927'}) =>
    PurchaseEntry(
      belongDate: DateTime(2026, 8, 5),
      spendDate: DateTime(2026, 8, 5),
      expenseCategory: '도서인쇄비',
      description: '8월 도서',
      vendor: '영풍문고',
      classCode: 3,
      className: '법인(신용)',
      cardNumber: cardNumber,
      totalAmount: 19000,
      supplyAmount: 19000,
      vatAmount: 0,
      createdBy: 'james@bodit.co',
      createdAt: DateTime(2026, 8, 5, 10),
    );

void main() {
  group('시트 10번 컬럼', () {
    test('카드번호 전체가 그대로 들어간다', () {
      // 컬럼 순서가 곧 계약이다. 마스크(`*`)도 그대로 둔다 — 카드사가 그렇게
      // 인쇄하므로 우리가 풀 수 있는 자리가 아니다.
      final row = _entry().toSheetRow();
      expect(row[9], '5531-46**-****-3927');
    });

    test('뒤 4자리만 아는 건은 그 네 자리만 들어간다', () {
      // 모르는 앞자리를 지어내지 않는다.
      expect(_entry(cardNumber: '3927').toSheetRow()[9], '3927');
    });
  });

  group('큐에 남아 있던 건', () {
    test('옛 키(cardLast4)로 저장된 건도 되살아난다', () {
      // 앱을 올리는 순간 전송 못 한 건이 기기에 있을 수 있다. 옛 키를
      // 무시하면 required 필드가 없어서 던지고, 사용자는 증빙을 처음부터
      // 다시 올린다.
      final json = _entry().toJson()
        ..remove('cardNumber')
        ..['cardLast4'] = '3927';

      final back = PurchaseEntry.fromJson(json);
      expect(back.cardNumber, '3927');
      expect(back.vendor, '영풍문고');
    });

    test('새 키가 있으면 옛 키는 무시한다', () {
      final json = _entry().toJson()..['cardLast4'] = '0000';
      expect(PurchaseEntry.fromJson(json).cardNumber, '5531-46**-****-3927');
    });

    test('왕복해도 값이 그대로다', () {
      final back = PurchaseEntry.fromJson(_entry().toJson());
      expect(back, _entry());
    });
  });
}
