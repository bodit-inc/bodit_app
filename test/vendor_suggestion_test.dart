/// `VendorSuggestion.fromRows` — 업체 이력에서 비목을 고르는 규칙.
///
/// 네트워크 없이 돈다. 세는 일을 `suggestForVendor` 안에 두면 Sheets 를
/// 띄워야만 확인할 수 있어서, 1등을 고르는 규칙이 조용히 틀려도 아무도 모른다.
///
/// 행 모양은 시트의 `E2:I` 와 같다: `비목 · 내역 · 업체명 · 분류코드 · 분류명`.
library;

import 'package:bodit_app/data/remote/sheets_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// 한 행. 분류명은 아무도 안 읽으므로 비워둔다.
List<Object?> row(String category, String desc, String vendor, Object? code) =>
    <Object?>[category, desc, vendor, code, ''];

void main() {
  test('이력이 하나뿐이면 "모두" 라고 적는다', () {
    final s = VendorSuggestion.fromRows([
      row('도서인쇄비', '8월 도서', '영풍문고', 11),
      row('도서인쇄비', '9월 도서', '영풍문고', 11),
    ], vendor: '영풍문고')!;

    expect(s.expenseCategory, '도서인쇄비');
    expect(s.matchCount, 2);
    expect(s.totalCount, 2);
    expect(s.reason, '2건 모두 도서인쇄비였습니다.');
    // 보여줄 다른 선택이 없다.
    expect(s.categoryTallies.length, 1);
  });

  test('이력이 갈리면 "N건 중 M건" 이다 — 예전에는 여기서도 "모두" 라고 했다', () {
    final s = VendorSuggestion.fromRows([
      for (var i = 0; i < 4; i++) row('도서인쇄비', '도서 $i', '영풍문고', 11),
      for (var i = 0; i < 3; i++) row('복리후생비', '간식 $i', '영풍문고', 11),
    ], vendor: '영풍문고')!;

    expect(s.reason, '7건 중 4건이 도서인쇄비였습니다.');
    expect(s.totalCount, 7);
    expect(s.matchCount, 4);
  });

  test('갈린 이력을 건수 많은 것부터 전부 돌려준다 — 나머지가 화면에서 사라지면 안 된다', () {
    final s = VendorSuggestion.fromRows([
      row('복리후생비', '간식', '영풍문고', 11),
      for (var i = 0; i < 3; i++) row('도서인쇄비', '도서 $i', '영풍문고', 11),
      row('소모품비', '문구', '영풍문고', 11),
      row('복리후생비', '간식2', '영풍문고', 11),
    ], vendor: '영풍문고')!;

    expect(s.categoryTallies.map((t) => t.label).toList(), [
      '도서인쇄비 3건',
      '복리후생비 2건',
      '소모품비 1건',
    ]);
  });

  test('비목은 **비목별** 건수로 고른다 — 분류코드로 쪼개면 1등이 뒤바뀐다', () {
    // 도서인쇄비는 5건이지만 분류코드가 44·11 로 갈려 있다. 조합으로 세면
    // 복리후생비(4건)가 1등이 되어, 더 자주 쓴 비목을 놓친다.
    final s = VendorSuggestion.fromRows([
      for (var i = 0; i < 3; i++) row('도서인쇄비', '도서 $i', '영풍문고', 44),
      for (var i = 0; i < 2; i++) row('도서인쇄비', '교재 $i', '영풍문고', 11),
      for (var i = 0; i < 4; i++) row('복리후생비', '간식 $i', '영풍문고', 44),
    ], vendor: '영풍문고')!;

    expect(s.expenseCategory, '도서인쇄비');
    expect(s.matchCount, 5);
  });

  test('건수가 같으면 시트에 먼저 나온 쪽이 먼저다 — 조회마다 칩 순서가 바뀌면 안 된다', () {
    List<String> order() => VendorSuggestion.fromRows([
      row('복리후생비', '간식', '영풍문고', 11),
      row('도서인쇄비', '도서', '영풍문고', 11),
      row('소모품비', '문구', '영풍문고', 11),
    ], vendor: '영풍문고')!.categoryTallies.map((t) => t.category).toList();

    expect(order(), ['복리후생비', '도서인쇄비', '소모품비']);
    // 같은 입력이면 같은 순서다(List.sort 는 안정 정렬이 아니다).
    expect(order(), order());
  });

  test('업체명은 공백·대소문자를 무시하고 맞춘다', () {
    final s = VendorSuggestion.fromRows([
      row('도서인쇄비', '도서', '  영풍 문고 ', 11),
    ], vendor: '영풍문고')!;

    expect(s.matchCount, 1);
  });

  test('다른 업체 행은 세지 않는다', () {
    expect(
      VendorSuggestion.fromRows([
        row('도서인쇄비', '도서', '교보문고', 11),
      ], vendor: '영풍문고'),
      isNull,
    );
  });

  test('비목이 비었거나 분류코드가 숫자가 아닌 행은 세지 않는다', () {
    final s = VendorSuggestion.fromRows([
      row('', '도서', '영풍문고', 11),
      row('도서인쇄비', '도서', '영풍문고', '분류없음'),
      row('도서인쇄비', '도서2', '영풍문고', 11),
    ], vendor: '영풍문고')!;

    expect(s.totalCount, 1);
    expect(s.reason, '1건 모두 도서인쇄비였습니다.');
  });

  test('업체명이 비면 조회하지 않는다 — 아무 행이나 걸린다', () {
    expect(
      VendorSuggestion.fromRows([row('도서인쇄비', '도서', '', 11)], vendor: '  '),
      isNull,
    );
  });

  test('내역은 최근 것부터 최대 6개, 중복을 지운다', () {
    final s = VendorSuggestion.fromRows([
      row('도서인쇄비', '1월 도서', '영풍문고', 11),
      for (var i = 2; i <= 8; i++) row('도서인쇄비', '$i월 도서', '영풍문고', 11),
      // 같은 내역이 다시 나오면 최신 자리로 올라온다.
      row('도서인쇄비', '1월 도서', '영풍문고', 11),
    ], vendor: '영풍문고')!;

    expect(s.recentDescriptions, [
      '1월 도서',
      '8월 도서',
      '7월 도서',
      '6월 도서',
      '5월 도서',
      '4월 도서',
    ]);
  });

  test('짧은 행은 건너뛴다 — 시트 끝의 덜 찬 행에서 던지면 추천이 통째로 날아간다', () {
    final s = VendorSuggestion.fromRows([
      <Object?>['도서인쇄비', '도서'],
      row('도서인쇄비', '도서', '영풍문고', 11),
    ], vendor: '영풍문고')!;

    expect(s.totalCount, 1);
  });
}
