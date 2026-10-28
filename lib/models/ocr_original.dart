/// OCR 이 읽은 **원래 값**.
///
/// ## 왜 따로 들고 있는가
///
/// `EntryDraft` 의 값은 사용자가 고치는 순간 덮인다. 그러면 "무엇으로
/// 인식했는지" 가 사라져서 두 가지를 못 한다:
///
///   - **다르게 고쳤다고 말해주기.** OCR 이 `영풍문고` 로 읽었는데 사용자가
///     `영풍문고(여의도)` 로 바꿨다면, 둘 중 하나는 틀렸다. 숫자 하나가
///     틀리면 분류가 통째로 바뀌고 시트는 append-only 라 되돌릴 수 없다
///   - **되돌리기.** 잘못 고쳤을 때 원래 값을 다시 찾을 방법이 없다
///
/// ## 왜 confidence 처럼 Map 이 아닌가
///
/// 날짜는 `DateTime`, 금액은 `int` 다. 문자열 맵에 넣으면 되돌릴 때 다시
/// 파싱해야 하고, 파싱이 실패하면 **조용히 되돌리기가 안 된다.** 필드가
/// 다섯 개뿐이라 타입을 지키는 쪽이 싸다.
///
/// 비목·분류는 여기 없다 — **영수증에 없는 항목이다.** 비목은 과거 이력,
/// 분류는 카드가 정한다(`EntryDraft.suggestedCategory`·`cardClass`).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'ocr_original.freezed.dart';

@freezed
abstract class OcrOriginal with _$OcrOriginal {
  const factory OcrOriginal({
    DateTime? belongDate,
    String? vendor,
    String? description,

    /// 뒤 4자리. 가려진 자리가 있으면 `766*` 처럼 들어온다.
    String? cardLast4,

    /// 통화의 최소 단위(원은 원, 달러는 센트) — `EntryDraft.totalAmount` 와 같다.
    int? totalAmount,
  }) = _OcrOriginal;
}
