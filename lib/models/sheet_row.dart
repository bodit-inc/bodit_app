/// 시트 한 행으로 직렬화할 수 있는 것.
///
/// ## 왜 인터페이스로 뽑았나
///
/// 지금은 매입내역(`PurchaseEntry`) 하나뿐이다. 그런데 다음 차수가 예정돼 있다:
/// 2차 사업비 사용내역, 3차 월결산 — **각각 다른 탭에 다른 컬럼 구성**으로 들어간다.
///
/// 인터페이스가 없으면 `SheetsRepository` 에 `appendPurchase`,
/// `appendBusinessExpense` 처럼 타입마다 함수가 하나씩 붙는다.
/// 이 한 줄이면 append 는 영원히 하나다.
///
/// 구현이 하나뿐인데 인터페이스를 만드는 건 보통 과한 짓이지만,
/// **두 번째 구현이 문서로 예고돼 있으면** 얘기가 다르다.
library;

/// 시트에 append 할 수 있는 도메인 객체.
abstract interface class SheetRow {
  /// 컬럼 순서대로 담은 한 행. **순서가 곧 계약이다** — 바꾸려면 위키부터.
  List<Object> toSheetRow();

  /// 어느 탭에 들어가는가. `_비목마스터` 같은 설정 탭이 아니라 데이터 탭 이름.
  String get sheetName;
}

/// 큐에 들어갈 수 있는 항목의 종류.
///
/// 큐는 항목을 JSON 으로 보관하는데, 꺼낼 때 **어떤 타입으로 되살릴지** 알아야 한다.
/// 지금 이 컬럼을 넣어두면 2차가 올 때 값 하나만 늘리면 된다.
/// 나중에 넣으면 스키마 마이그레이션에 기존 행 백필까지 붙는다.
enum EntryKind {
  /// 매입내역 (1차).
  purchase('purchase');

  EntryKind(this.wireName);

  /// DB 에 저장되는 문자열. **enum 이름이 아니라 이 값을 쓴다** —
  /// 나중에 Dart 쪽 이름을 바꿔도 저장된 데이터가 안 깨진다.
  final String wireName;

  static EntryKind fromWire(String v) => EntryKind.values.firstWhere(
        (e) => e.wireName == v,
        orElse: () => throw ArgumentError('알 수 없는 항목 종류: $v'),
      );
}
