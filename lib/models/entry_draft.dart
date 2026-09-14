/// 검토 중인 매입내역 한 건.
///
/// [PurchaseEntry] 와 왜 따로 두는가: 그쪽은 시트에 들어갈 **완성된** 행이라
/// 모든 필드가 non-null 이다. 검토 화면은 OCR 이 못 읽은 칸이 비어 있는
/// 중간 상태를 다뤄야 하므로 전부 nullable 인 별도 타입이 필요하다.
///
/// `toEntry()` 가 성공하면 그때 제출할 수 있다.
library;

import 'package:bodit_app/core/utils/filename.dart';
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
    int? totalAmount,
    int? supplyAmount,
    int? vatAmount,

    /// 영수증에 부가세가 인쇄돼 있었는지. false 면 "1.1로 나누기" 를 권한다.
    @Default(false) bool vatPrinted,
    @Default('') String note,
    @Default('') String settlementAccount,
    @Default('영수증') String evidenceType,

    /// 사용자가 파일명을 직접 고쳤으면 그 값. null 이면 자동 생성한다.
    String? filenameOverride,

    /// 과거 이력 추천의 근거. 화면에 그대로 보여준다.
    String? suggestionReason,
  }) = _EntryDraft;

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
