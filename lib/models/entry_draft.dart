/// 검토 중인 매입내역 한 건.
///
/// [PurchaseEntry] 와 왜 따로 두는가: 그쪽은 시트에 들어갈 **완성된** 행이라
/// 모든 필드가 non-null 이다. 검토 화면은 OCR 이 못 읽은 칸이 비어 있는
/// 중간 상태를 다뤄야 하므로 전부 nullable 인 별도 타입이 필요하다.
///
/// `toEntry()` 가 성공하면 그때 제출할 수 있다.
library;

import 'package:bodit_app/core/utils/filename.dart';
import 'package:bodit_app/models/class_choice.dart';
import 'package:bodit_app/models/evidence_type.dart';
import 'package:bodit_app/models/purchase_entry.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'entry_draft.freezed.dart';

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

    /// 카드로 분류를 못 정한 이유. 화면이 배너로 보여준다.
    ///
    /// **조용히 비워두면 안 된다** — 사용자는 분류 칸이 왜 비었는지 모른 채
    /// 44개 목록에서 직접 찾게 된다. 못 찾았으면 못 찾았다고 말한다.
    String? cardNotice,

    /// 같은 업체로 과거에 쓴 내역 후보. **자동으로 채우지 않는다** —
    /// 내역은 건마다 달라서("8월 도서" → "9월 도서") 지난 값을 넣으면
    /// 9월에 8월 것이 조용히 들어간다. 고르는 건 사용자가 한다.
    @Default(<String>[]) List<String> descriptionSuggestions,
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
  bool get isComplete =>
      belongDate != null &&
      (vendor ?? '').isNotEmpty &&
      (description ?? '').isNotEmpty &&
      (expenseCategory ?? '').isNotEmpty &&
      classCode != null &&
      totalAmount != null;

  /// 아직 비어 있는 칸의 이름들. 제출 버튼 옆에 그대로 보여준다.
  List<String> get missingFields => <String>[
    if (belongDate == null) '소속날짜',
    if ((vendor ?? '').isEmpty) '업체명',
    if ((description ?? '').isEmpty) '내역',
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
      description: description!,
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
