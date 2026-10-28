/// 검토 중인 매입내역 한 건.
///
/// [PurchaseEntry] 와 왜 따로 두는가: 그쪽은 시트에 들어갈 **완성된** 행이라
/// 모든 필드가 non-null 이다. 검토 화면은 OCR 이 못 읽은 칸이 비어 있는
/// 중간 상태를 다뤄야 하므로 전부 nullable 인 별도 타입이 필요하다.
///
/// `toEntry()` 가 성공하면 그때 제출할 수 있다.
library;

import 'package:bodit_app/core/utils/filename.dart';
import 'package:bodit_app/models/certainty.dart';
import 'package:bodit_app/models/class_choice.dart';
import 'package:bodit_app/models/evidence_type.dart';
import 'package:bodit_app/models/purchase_entry.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'entry_draft.freezed.dart';

/// 내역을 모를 때 대신 들어가는 값.
///
/// 예전엔 내역이 **필수**라 모르면 제출 자체가 막혔다. 그런데 영수증만 보고는
/// 무슨 건인지 모르는 경우가 실제로 있고(대신 결제, 공용 물품 등), 그때 사용자는
/// 아무 말이나 지어내거나 제출을 포기했다. 둘 다 회계 담당자에게 더 나쁘다.
///
/// 그래서 비워둔 채 넘기고 **시트에서 눈에 띄게** 만든다. 담당자가 이 값을
/// 검색해 한 번에 모아볼 수 있다.
const needsOpsReview = '운영팀 확인 요청';

@freezed
abstract class EntryDraft with _$EntryDraft {
  const factory EntryDraft({
    /// 기기에 보관 중인 증빙 원본 경로.
    required String evidencePath,
    DateTime? belongDate,
    DateTime? spendDate,
    String? vendor,
    String? description,
    String? expenseCategory,
    int? classCode,
    String? className,
    String? cardLast4,

    /// ISO 4217 코드. 금액 세 칸은 이 통화의 **최소 단위**로 들고 있다.
    @Default('KRW') String currency,
    int? totalAmount,
    int? supplyAmount,
    int? vatAmount,

    /// 영수증에 부가세가 인쇄돼 있었는지. false 면 "1.1로 나누기" 를 권한다.
    @Default(false) bool vatPrinted,

    /// 사용자가 **[1.1로 나누기] 를 눌렀는지.**
    ///
    /// 이건 금액이 아니라 **판단**을 기억하는 값이다 — "이 건은 과세다" 라고
    /// 사용자가 정한 것. 그래서 총금액을 고치면 같은 판단을 다시 적용할 수 있다.
    /// 이 표시가 없으면 금액을 고칠 때마다 버튼을 다시 눌러야 하고,
    /// 안 누르면 옛 공급가액이 새 총액과 어긋난 채로 남는다.
    @Default(false) bool vatSplitApplied,
    @Default('') String note,
    @Default('') String settlementAccount,
    @Default(defaultEvidenceType) String evidenceType,

    /// 사용자가 파일명을 직접 고쳤으면 그 값. null 이면 자동 생성한다.
    String? filenameOverride,

    /// **비목** 추천의 근거(과거 이력). 화면에 그대로 보여준다.
    String? suggestionReason,

    /// **분류** 추천의 근거(카드). 비목과 출처가 달라서 줄을 따로 쓴다 —
    /// 한 줄에 합치면 어느 쪽이 추측이고 어느 쪽이 사실인지 섞인다.
    String? classReason,

    /// 뒤 4자리가 겹쳐서 분류를 못 정했을 때의 후보들.
    ///
    /// **비어 있지 않으면 분류를 자동으로 채우지 않았다는 뜻이다.**
    /// 조용히 첫 번째를 고르면 겹치는 순간부터 절반이 틀린 예산에 잡힌다.
    @Default(<ClassChoice>[]) List<ClassChoice> classSuggestions,

    /// OCR 항목별 확신도(0.0~1.0). 키는 OCR 스키마의 필드명이다.
    ///
    /// **없는 키는 "모른다" 다.** 비어 있다고 전부 확신한 것으로 치면
    /// 경고가 거짓말이 된다 — 직접 친 값과 모델이 찍은 값이 구분되지 않는다.
    @Default(<String, double>{}) Map<String, double> confidence,

    /// 사진이 읽을 만하지 않았을 때 모델이 적어준 한국어 한 문장.
    /// 화면이 "다시 찍기" 와 함께 띄운다.
    String? imageProblem,

    /// 카드로 분류를 못 정한 이유. 화면이 배너로 보여준다.
    ///
    /// **조용히 비워두면 안 된다** — 사용자는 분류 칸이 왜 비었는지 모른 채
    /// 44개 목록에서 직접 찾게 된다. 못 찾았으면 못 찾았다고 말한다.
    String? cardNotice,

    /// 같은 업체로 과거에 쓴 내역 후보. **자동으로 채우지 않는다** —
    /// 내역은 건마다 달라서("8월 도서" → "9월 도서") 지난 값을 넣으면
    /// 9월에 8월 것이 조용히 들어간다. 고르는 건 사용자가 한다.
    @Default(<String>[]) List<String> descriptionSuggestions,

    /// 업체 이력이 제안한 비목. **추천을 적용한 뒤에도 들고 있는다** —
    /// 사용자가 다른 값으로 고쳤는지는 원래 값이 남아 있어야 알 수 있다.
    /// `suggestionReason` 은 근거 문구이고 값이 아니다.
    String? suggestedCategory,

    /// 카드가 정한 분류. **코드와 이름을 같이 들고 있는다** — 화면에 코드만
    /// 보여주면 제출자는 `44` 가 무슨 예산인지 모른다(코드로 말하는 건
    /// 회계 담당자다).
    ///
    /// 사용자가 picker 에서 다른 분류를 고르면 `classCode` 만 바뀌고 이 값은
    /// 남는다. 그 차이를 화면이 말해준다 — **분류는 카드가 이미 정해놓은
    /// 사실**이라, 벗어나는 것은 비목을 고치는 것보다 무거운 일이다.
    ClassChoice? cardClass,
  }) = _EntryDraft;

  /// 이미 제출해 큐에 들어간 건을 다시 편집할 때. 전송 전이라면 고칠 수 있다.
  ///
  /// 시트에 **이미 들어간 행은 고치지 않는다**(ADR Decision 3) — 여기서 되살리는
  /// 것은 아직 아무 데도 안 나간 건이라 그 제약과 무관하다.
  ///
  /// [filename] 은 큐에 저장돼 있던 값을 그대로 쓴다. 사용자가 손으로 고쳤을 수
  /// 있고, 그렇다면 항목을 다시 바꿔도 그 이름을 지켜야 한다.
  factory EntryDraft.fromEntry(
    PurchaseEntry e, {
    required String evidencePath,
    required String filename,
  }) {
    return EntryDraft(
      evidencePath: evidencePath,
      belongDate: e.belongDate,
      spendDate: e.spendDate,
      vendor: e.vendor,
      description: e.description,
      expenseCategory: e.expenseCategory,
      classCode: e.classCode,
      className: e.className,
      cardLast4: e.cardLast4,
      currency: e.currency,
      totalAmount: e.totalAmount,
      supplyAmount: e.supplyAmount,
      vatAmount: e.vatAmount,
      // 이미 확정된 금액이라 "부가세가 안 찍혔다" 배너를 다시 띄우지 않는다.
      vatPrinted: true,
      note: e.note,
      settlementAccount: e.settlementAccount,
      filenameOverride: filename,
    );
  }

  const EntryDraft._();

  /// 그 항목의 확신도 **단계**.
  ///
  /// 기준을 0.7 로 둔 건 **경고가 드물어야 쓸모 있기 때문**이다. 절반이
  /// 노랗게 뜨면 아무도 안 본다. 모델이 "읽긴 했는데 자신 없다" 고 말한
  /// 것만 집어낸다.
  ///
  /// 0.4 아래를 따로 둔 건 `0.39` 와 `0.69` 가 **할 일이 다르기** 때문이다.
  /// 앞쪽은 사실상 못 읽은 것이라 값을 믿을 수 없고, 뒤쪽은 한 번 훑으면
  /// 된다. 예전엔 둘이 똑같이 떠서, 거의 못 읽은 값도 "확인해 주세요" 로만
  /// 보였다.
  ///
  /// 확신도가 아예 없으면(직접 친 값, OCR 실패, PDF) [Certainty.unknown] 이다 —
  /// 모르는 것을 틀렸다고 말하지 않는다.
  Certainty certaintyOf(String ocrField) {
    final c = confidence[ocrField];
    if (c == null) return Certainty.unknown;
    if (c < 0.4) return Certainty.poor;
    if (c < 0.7) return Certainty.check;
    return Certainty.ok;
  }

  /// 그 항목을 사람이 한 번 더 봐야 하는가. 단계가 필요하면
  /// [certaintyOf] 를 쓴다.
  bool isUncertain(String ocrField) => certaintyOf(ocrField).needsAttention;

  /// 비목을 **추천과 다르게** 고쳤는가.
  ///
  /// 비목 추천은 과거 이력이라 **추측이다** — "영풍문고는 지난 6건 모두
  /// 도서인쇄비였다" 는 경향일 뿐이고, 이번 건이 다를 수 있다. 그래서
  /// 벗어나는 것은 정상 동작이고, 화면도 조용히 알려주기만 한다.
  bool get categoryDiffersFromSuggestion {
    final s = suggestedCategory;
    final v = expenseCategory;
    return s != null && v != null && s != v;
  }

  /// 분류를 **카드가 정한 것과 다르게** 고쳤는가.
  ///
  /// 분류는 추측이 아니다 — 어느 예산으로 집행됐는지는 긁은 카드가 이미
  /// 정해놨다. 벗어나면 그 카드의 예산이 아닌 곳에 잡히므로, 비목과 달리
  /// **분명하게** 말해야 한다.
  bool get classDiffersFromCard {
    final c = cardClass;
    final v = classCode;
    return c != null && v != null && c.code != v;
  }

  /// 저장될 파일명. 항목이 바뀌면 따라 바뀌고, 사용자가 덮어쓸 수 있다.
  ///
  /// 사용자가 직접 친 값에도 **치환 규칙을 적용한다** — `/` 하나로 Drive
  /// 동기화가 깨진다.
  String get filename {
    final override = filenameOverride;
    if (override != null) return sanitizeSegment(override);
    return buildEvidenceFilename(
      belongDate: belongDate ?? DateTime.now(),
      vendor: vendor ?? '',
      description: description ?? '',
      evidenceType: evidenceType,
      amount: totalAmount ?? 0,
    );
  }

  /// 제출에 필요한 칸이 다 찼는지.
  /// **내역은 빠져 있다** — 모르면 [needsOpsReview] 로 채워 넘긴다.
  /// 지어낸 내역보다 "확인 요청" 이 회계 담당자에게 낫다.
  bool get isComplete =>
      belongDate != null &&
      (vendor ?? '').isNotEmpty &&
      (expenseCategory ?? '').isNotEmpty &&
      classCode != null &&
      totalAmount != null;

  /// 아직 비어 있는 칸의 이름들. 제출 버튼 옆에 그대로 보여준다.
  List<String> get missingFields => <String>[
    if (belongDate == null) '소속날짜',
    if ((vendor ?? '').isEmpty) '업체명',
    if ((expenseCategory ?? '').isEmpty) '비목',
    if (classCode == null) '분류코드',
    if (totalAmount == null) '총금액',
  ];

  /// 시트에 넣을 완성 행으로 바꾼다. [isComplete] 가 false 면 던진다.
  PurchaseEntry toEntry({required String createdBy}) {
    if (!isComplete) {
      throw StateError('아직 비어 있는 항목이 있습니다: ${missingFields.join(', ')}');
    }
    final total = totalAmount!;
    return PurchaseEntry(
      belongDate: belongDate!,
      // 지출날짜는 영수증에 없다. 사용자가 안 고쳤으면 소속날짜를 쓴다.
      spendDate: spendDate ?? belongDate!,
      expenseCategory: expenseCategory!,
      // 비어 있으면 지어내지 않고 운영팀에게 넘긴다.
      description: (description ?? '').isEmpty ? needsOpsReview : description!,
      vendor: vendor!,
      classCode: classCode!,
      className: className ?? '',
      cardLast4: cardLast4 ?? '',
      currency: currency,
      totalAmount: total,
      // 공급가액이 안 찍혀 있으면 총액을 그대로 둔다. 1.1로 나누지 않는다 —
      // 면세면 그게 맞고, 과세면 사용자가 [1.1로 나누기] 를 누른다.
      supplyAmount: supplyAmount ?? total,
      vatAmount: vatAmount ?? 0,
      note: note,
      settlementAccount: settlementAccount,
      createdBy: createdBy,
      createdAt: DateTime.now(),
    );
  }
}
