/// `CategoryGuess.fromRows` — 업체명이 **안 맞았을 때** 비목을 짐작하는 규칙.
///
/// 네트워크 없이 돈다. 이 규칙이 조용히 틀리면 비목 화면의 칩이 엉뚱한 비목을
/// 맨 앞에 띄우는데, 그걸 눌러 제출한 행은 append-only 라 되돌릴 수 없다.
///
/// 행 모양은 시트의 `E2:I` 와 같다: `비목 · 내역 · 업체명 · 분류코드 · 분류명`.
library;

import 'package:bodit_app/data/remote/sheets_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// 한 행. 분류명은 아무도 안 읽으므로 비워둔다.
List<Object?> row(String category, String desc, String vendor, Object? code) =>
    <Object?>[category, desc, vendor, code, ''];

void main() {
  group('같은 가게로 보는 기준 (`similarVendor`)', () {
    test('한쪽이 다른 쪽을 품으면 같은 가게다', () {
      expect(CategoryGuess.similarVendor('영풍문고', '영풍문고 종로점'), isTrue);
      expect(CategoryGuess.similarVendor('영풍문고 종로점', '영풍문고'), isTrue);
      // 공백·대소문자 표기 차이로 못 찾는 걸 막는다.
      expect(CategoryGuess.similarVendor('GS25 역삼', 'gs25역삼점'), isTrue);
    });

    test('양쪽에 지점명이 붙어도 앞머리가 같으면 같은 가게다 — 품기만으로는 못 걸린다', () {
      expect(
        CategoryGuess.similarVendor('영풍문고 종로점', '영풍문고 강남점'),
        isTrue,
      );
      expect(CategoryGuess.similarVendor('다이소 역삼점', '다이소 서초점'), isTrue);
    });

    test('앞 두 글자만 같은 것은 남의 가게다 — 그래서 기준이 세 글자다', () {
      expect(CategoryGuess.similarVendor('서울우유', '서울식당'), isFalse);
      expect(CategoryGuess.similarVendor('김밥천국', '김밥나라'), isFalse);
    });

    test('한 글자는 보지 않는다 — 수십 개가 걸리면 추측이 아니라 소음이다', () {
      expect(CategoryGuess.similarVendor('G', 'GS25 역삼점'), isFalse);
      expect(CategoryGuess.similarVendor('영풍문고', '문'), isFalse);
    });
  });

  group('업체명이 비슷한 행', () {
    test('지점명만 다른 업체를 찾는다 — 정확히 안 맞아서 추천이 비었을 뿐이다', () {
      final g = CategoryGuess.fromRows([
        row('도서인쇄비', '8월 도서', '영풍문고 종로점', 11),
        row('도서인쇄비', '9월 도서', '영풍문고 강남점', 11),
        row('복리후생비', '간식', 'GS25', 3),
      ], vendor: '영풍문고')!;

      expect(g.tallies.first.category, '도서인쇄비');
      expect(g.tallies.first.count, 2);
      expect(g.reason, '업체명이 비슷한 과거 2건에서 쓴 비목입니다.');
    });

    test('한 글자로는 찾지 않는다 — 수십 개가 걸리면 추측이 아니라 소음이다', () {
      final g = CategoryGuess.fromRows([
        row('복리후생비', '간식', 'GS25 역삼점', 3),
      ], vendor: 'G');

      expect(g, isNull);
    });

    test('업체명이 걸리면 내역 쪽은 섞지 않는다 — 근거 문구가 둘 중 무엇인지 말할 수 없게 된다', () {
      final g = CategoryGuess.fromRows([
        row('도서인쇄비', '명함 인쇄', '영풍문고 종로점', 11),
        for (var i = 0; i < 5; i++) row('복리후생비', '명함 인쇄', '성원기획 $i', 3),
      ], vendor: '영풍문고', description: '명함 인쇄')!;

      expect(g.tallies.length, 1);
      expect(g.tallies.first.category, '도서인쇄비');
      expect(g.reason, contains('업체명이 비슷한'));
    });
  });

  group('비슷한 업체면 내역 후보도 같이 온다', () {
    test('지점명이 달라 업체명이 못 맞은 건에도 내역을 띄운다 — 예전엔 그 칸이 통째로 비었다', () {
      final g = CategoryGuess.fromRows([
        row('도서인쇄비', '7월 도서', '영풍문고 종로점', 11),
        row('도서인쇄비', '8월 도서', '영풍문고 강남점', 11),
        row('복리후생비', '간식', 'GS25', 3),
      ], vendor: '영풍문고 홍대점')!;

      // 최근 것부터. 시트가 append-only 라 뒤에 있는 것이 최근이다.
      expect(g.recentDescriptions, <String>['8월 도서', '7월 도서']);
    });

    test('내역이 겹쳐서 걸린 경우는 내역 후보를 주지 않는다 — 남의 가게 문구다', () {
      final g = CategoryGuess.fromRows([
        row('도서인쇄비', '8월 도서', '교보문고', 11),
      ], vendor: '리브로', description: '9월 도서')!;

      // 비목은 가게가 달라도 같을 수 있지만(도서는 어디서 사도 도서인쇄비)
      // 내역은 "이 건에 무엇을 샀나" 라서 남의 가게 문구를 권하면 안 된다.
      expect(g.tallies.first.category, '도서인쇄비');
      expect(g.recentDescriptions, isEmpty);
    });

    test('내역이 빈 과거 행은 후보에 넣지 않는다', () {
      final g = CategoryGuess.fromRows([
        row('도서인쇄비', '', '영풍문고 종로점', 11),
      ], vendor: '영풍문고')!;

      expect(g.recentDescriptions, isEmpty);
    });
  });

  group('내역에 같은 말이 들어간 행', () {
    test('업체가 처음이어도 내역이 겹치면 짐작한다', () {
      final g = CategoryGuess.fromRows([
        row('도서인쇄비', '8월 도서', '영풍문고', 11),
        row('도서인쇄비', '7월 도서', '교보문고', 11),
        row('복리후생비', '간식', 'GS25', 3),
      ], vendor: '리브로', description: '9월 도서')!;

      expect(g.tallies.first.category, '도서인쇄비');
      expect(g.tallies.first.count, 2);
      expect(g.reason, "내역에 '도서'가 들어간 과거 2건에서 쓴 비목입니다.");
    });

    test('받침이 있으면 조사가 바뀐다 — 근거 문구는 사용자가 읽는 유일한 설명이다', () {
      final g = CategoryGuess.fromRows([
        row('소모품비', '책상 2개', '이케아', 3),
      ], description: '책상 구입')!;

      expect(g.reason, "내역에 '책상'이 들어간 과거 1건에서 쓴 비목입니다.");
    });

    test('숫자가 섞인 말로는 찾지 않는다 — `8월` 은 그 달의 모든 비목을 끌어온다', () {
      final g = CategoryGuess.fromRows([
        row('복리후생비', '8월 식대', '김밥천국', 3),
        row('여비교통비', '8월 택시', '카카오T', 3),
      ], description: '8월');

      expect(g, isNull);
    });

    test('겹치는 말이 둘이면 **더 많이 걸린 말 하나**만 쓴다', () {
      final g = CategoryGuess.fromRows([
        row('도서인쇄비', '도서 구입', '교보문고', 11),
        row('도서인쇄비', '도서 구입', '리브로', 11),
        row('복리후생비', '간식 구입', 'GS25', 3),
      ], description: '도서 구입')!;

      // `구입` 은 세 건, `도서` 는 두 건이다. 많이 걸린 `구입` 을 쓴다 —
      // 둘을 합치면 근거 건수가 다섯이 되는데 실제 행은 셋이다.
      expect(g.reason, "내역에 '구입'이 들어간 과거 3건에서 쓴 비목입니다.");
      expect(g.tallies.first.category, '도서인쇄비');
      expect(g.tallies.first.count, 2);
    });
  });

  test('완성되지 않은 행은 근거가 아니다 — 비목이 비었거나 분류코드가 숫자가 아닌 행', () {
    final g = CategoryGuess.fromRows([
      row('', '8월 도서', '영풍문고 종로점', 11),
      row('도서인쇄비', '8월 도서', '영풍문고 종로점', '미정'),
    ], vendor: '영풍문고');

    expect(g, isNull);
  });

  test('후보는 셋까지 — 더 띄우면 아래 전체 목록과 하는 일이 같아진다', () {
    final g = CategoryGuess.fromRows([
      for (final c in ['가비', '나비', '다비', '라비', '마비'])
        row(c, '도서', '영풍문고 $c점', 11),
    ], vendor: '영풍문고')!;

    expect(g.tallies.length, CategoryGuess.maxCandidates);
    expect(g.reason, '업체명이 비슷한 과거 5건에서 쓴 비목입니다.');
  });

  test('동률이면 시트에 먼저 나온 쪽이 먼저다 — 안 그러면 칩 순서가 조회마다 바뀐다', () {
    final g = CategoryGuess.fromRows([
      row('도서인쇄비', '도서', '영풍문고 A점', 11),
      row('복리후생비', '도서', '영풍문고 B점', 3),
    ], vendor: '영풍문고')!;

    expect(
      g.tallies.map((t) => t.category).toList(),
      <String>['도서인쇄비', '복리후생비'],
    );
  });

  group('VendorLookup — 한 번 읽어 추천과 추측을 같이 만든다', () {
    test('업체명이 정확히 맞으면 추측은 만들지 않는다', () {
      final l = VendorLookup.fromRows([
        row('도서인쇄비', '8월 도서', '영풍문고', 11),
      ], vendor: '영풍문고', description: '9월 도서');

      expect(l.suggestion, isNotNull);
      expect(l.suggestion!.expenseCategory, '도서인쇄비');
      // 기록이 있는데 짐작을 같이 띄우면 어느 쪽이 근거 있는 값인지 흐려진다.
      expect(l.guess, isNull);
    });

    test('내역 후보도 그 이력에서 같이 온다 — 비목과 **같은 한 번의 일치**에 달려 있다', () {
      // 비목 추천과 내역 후보가 한 조회에서 같이 나온다는 사실을 박아둔다.
      // 업체명이 안 맞으면 둘이 **같이** 비는데, 그걸 모르면 내역 추천이
      // 사라진 줄 알고 멀쩡한 코드를 뒤지게 된다(실제로 그랬다).
      final matched = VendorLookup.fromRows([
        row('도서인쇄비', '8월 도서', '영풍문고', 11),
        row('도서인쇄비', '9월 도서', '영풍문고', 11),
      ], vendor: '영풍문고');
      expect(matched.suggestion!.recentDescriptions, <String>[
        '9월 도서',
        '8월 도서',
      ]);

      // 지점명이 붙어 안 맞으면 **짐작 쪽에서** 둘이 같이 온다.
      // 화면 라벨만 달라진다(`비슷한 업체로 전에 쓴 내역`) —
      // 다른 지점 것을 "이 업체" 것이라고 적으면 확인 없이 고른다.
      final missed = VendorLookup.fromRows([
        row('도서인쇄비', '8월 도서', '영풍문고 종로점', 11),
      ], vendor: '영풍문고');
      expect(missed.suggestion, isNull);
      expect(missed.guess!.tallies.first.category, '도서인쇄비');
      expect(missed.guess!.recentDescriptions, <String>['8월 도서']);
    });

    test('OCR 이 상호를 못 읽어도 내역으로 추측한다 — 그때가 사용자가 가장 막막한 경우다', () {
      final l = VendorLookup.fromRows([
        row('도서인쇄비', '8월 도서', '영풍문고', 11),
      ], description: '9월 도서');

      expect(l.suggestion, isNull);
      expect(l.guess, isNotNull);
      expect(l.guess!.tallies.first.category, '도서인쇄비');
    });

    test('근거가 하나도 없으면 둘 다 비운다 — 지어내지 않는다', () {
      final l = VendorLookup.fromRows([
        row('복리후생비', '간식', 'GS25', 3),
      ], vendor: '처음보는가게', description: '무엇인가');

      expect(l.suggestion, isNull);
      expect(l.guess, isNull);
    });
  });
}
