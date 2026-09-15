import 'package:bodit_app/core/utils/currency.dart';
import 'package:bodit_app/models/sheet_row.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'purchase_entry.freezed.dart';
part 'purchase_entry.g.dart';

/// 매입내역 한 건.
///
/// 컬럼 계약의 단일 원천은 위키다:
///   ~/llm-wiki-template/wiki/projects/bodit-app/sheet-schema.md
///
/// ## 왜 앱이 18개 컬럼을 **전부** 계산하는가
///
/// 원래 설계는 해당년도·해당월·분류명을 시트의 `ARRAYFORMULA` 에 맡기는 것이었다.
/// 코드를 쓰면서 그게 안 된다는 걸 확인했다:
///
///   `values.append` 는 **A열부터 연속된 한 행**을 쓴다. 그런데 ARRAYFORMULA 는
///   1행에서 아래로 spill 하므로, 그 범위 안의 셀에 값을 쓰면 spill 이 막혀
///   **컬럼 전체가 `#REF!` 로 죽는다.**
///
/// 수식 컬럼만 건너뛰고 쓰는 방법은 없다(A·B·I 가 떨어져 있어 연속 범위가 아니다).
/// 앱이 유일한 writer 이므로 앱이 다 계산하는 쪽이 맞다. 수식을 아예 쓰지 않는다.
@freezed
abstract class PurchaseEntry with _$PurchaseEntry implements SheetRow {
  const factory({
    /// 계산서 발행일 또는 카드 결제일. 해당년도·해당월의 기준이 된다.
    required DateTime belongDate,

    /// 실제로 비용을 집행한 날. 영수증에 없어서 기본값은 [belongDate].
    required DateTime spendDate,

    /// 비목. 34개 중 하나 — `_비목마스터` 탭에서 읽는다.
    /// **OCR 로 뽑을 수 없다** (영수증에 안 적혀 있다). 과거 이력 추천이 담당한다.
    required String expenseCategory,

    /// 매입 건 상세.
    required String description,

    /// 업체명. 과거 이력 추천의 **조회 키**다.
    required String vendor,

    /// 분류코드. `_분류마스터` 탭에서 분류명으로 풀린다.
    required int classCode,

    /// 분류명. [classCode] 로 마스터에서 찾아 채운다.
    required String className,

    /// 카드 뒤 4자리만. **앞자리는 OCR 결과에서도 즉시 버린다.**
    required String cardLast4,

    required int totalAmount, required int supplyAmount, /// **0원인 경우가 있다** (도서 등 면세). 자동 계산하지 않는다.
    required int vatAmount, /// 제출자 계정. OAuth 로그인에서 가져온다.
    required String createdBy, required DateTime createdAt, /// 공급가액 + 부가세.
    /// ISO 4217 코드. 기본은 원화다.
    ///
    /// **금액 세 칸은 이 통화의 최소 단위**로 들고 있다 —
    /// 원화는 소수점이 0 이라 그대로지만 달러는 센트다.
    /// 시트에 쓸 때 `Currency.toSheetValue` 로 나눈다.
    @Default('KRW') String currency,

    /// 일부 비목(금형제작비·재료비)에 한해 `FH` / `BS`.
    @Default('') String note,

    /// 규칙 미정.
    @Default('') String settlementAccount,

    /// Drive 파일 URL. 업로드 후에 채워진다.
    @Default('') String evidenceUrl,
  }) = _PurchaseEntry;

  const new _();

  factory fromJson(Map<String, dynamic> json) =>
      _$PurchaseEntryFromJson(json);

  /// 소속날짜에서 파생. 시트 1번 컬럼.
  int get belongYear => belongDate.year;

  /// 소속날짜에서 파생. 시트 2번 컬럼.
  int get belongMonth => belongDate.month;

  @override
  String get sheetName => '매입내역';

  Currency get _cur => currencyOf(currency);

  /// 외화면 비고 앞에 통화를 붙인다.
  ///
  /// 시트에 통화 컬럼이 없다(18칸 계약). 그렇다고 `12.99` 만 적어두면 회계
  /// 담당자가 원화로 읽는다 — **금액 칸만 보고는 구분할 수 없다.**
  /// 비고는 자유 입력 칸이라 여기에 얹는 게 계약을 안 깨는 유일한 자리다.
  ///
  /// 제대로 하려면 통화 컬럼을 하나 더 두는 게 맞다. 회계 담당자와 합의가
  /// 필요해서 지금은 이렇게 둔다 — 위키의 열린 질문에 올려뒀다.
  String get _noteWithCurrency {
    if (currency == 'KRW') return note;
    return note.isEmpty ? '[$currency]' : '[$currency] $note';
  }

  /// 시트에 append 할 한 행. **컬럼 순서가 곧 계약이다** — 바꾸려면 위키부터.
  @override
  List<Object> toSheetRow() => [
        belongYear, //          1  해당년도
        belongMonth, //         2  해당월
        _date(belongDate), //   3  소속날짜
        _date(spendDate), //    4  지출날짜
        expenseCategory, //     5  비목
        description, //         6  내역
        vendor, //              7  업체명
        classCode, //           8  분류코드
        className, //           9  분류명
        cardLast4, //          10  카드번호
        _cur.toSheetValue(totalAmount), //  11  총금액
        _cur.toSheetValue(supplyAmount), // 12  공급가액
        _cur.toSheetValue(vatAmount), //    13  부가세
        _noteWithCurrency, //  14  비고
        settlementAccount, //  15  결산계정
        createdBy, //          16
        createdAt.toIso8601String(), // 17
        evidenceUrl, //        18
      ];

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// 공급가액·부가세를 총액에서 1.1로 나눠 채운다.
///
/// **자동으로 부르지 않는다.** 면세(도서 등)는 부가세가 0원이라 자동 계산하면
/// 틀린다. 사용자가 검토 화면에서 [1.1로 나누기] 를 눌렀을 때만 쓴다.
({int supply, int vat}) splitVat(int total) {
  final supply = (total / 1.1).round();
  return (supply: supply, vat: total - supply);
}
