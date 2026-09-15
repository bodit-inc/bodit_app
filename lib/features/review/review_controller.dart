/// 검토 화면의 상태. 촬영 → OCR → 추천 → 확인 → 큐 적재까지를 들고 있다.
///
/// 여러 장을 한 번에 다루므로 draft 를 **목록**으로 갖는다(시안 ⑥).
/// 한 장이면 목록 길이가 1일 뿐, 코드 경로는 같다.
library;

import 'dart:convert';

import 'package:bodit_app/data/local/queue_db.dart';
import 'package:bodit_app/data/providers.dart';
import 'package:bodit_app/features/auth/auth_controller.dart';
import 'package:bodit_app/features/capture/capture_service.dart';
import 'package:bodit_app/models/entry_draft.dart';
import 'package:bodit_app/models/purchase_entry.dart';
import 'package:bodit_app/models/sheet_row.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

final captureServiceProvider = Provider<CaptureService>((ref) {
  return const CaptureService();
});

class ReviewState {
  const ReviewState({
    this.drafts = const <EntryDraft>[],
    this.selected = 0,
    this.isReading = false,
    this.error,
  });

  final List<EntryDraft> drafts;

  /// 여러 건일 때 지금 보고 있는 건.
  final int selected;

  /// OCR 진행 중 (시안 ④).
  final bool isReading;

  /// 예외 **원문**. 사람이 읽을 문구는 화면이 붙인다
  /// (`ErrorDisclosure` 가 한 줄 + 접힌 원문으로 보여준다).
  final String? error;

  EntryDraft? get current =>
      selected < drafts.length ? drafts[selected] : null;

  bool get isMulti => drafts.length > 1;

  /// 모든 건이 제출 가능한 상태인지.
  bool get allComplete =>
      drafts.isNotEmpty && drafts.every((d) => d.isComplete);

  ReviewState copyWith({
    List<EntryDraft>? drafts,
    int? selected,
    bool? isReading,
    String? error,
    bool clearError = false,
  }) {
    return ReviewState(
      drafts: drafts ?? this.drafts,
      selected: selected ?? this.selected,
      isReading: isReading ?? this.isReading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class ReviewController extends Notifier<ReviewState> {
  @override
  ReviewState build() => const ReviewState();

  static const _uuid = Uuid();

  /// 증빙을 받아 draft 를 만들고 OCR 을 돌린다.
  Future<void> load(List<CapturedEvidence> evidence) async {
    if (evidence.isEmpty) return;

    state = ReviewState(
      drafts: <EntryDraft>[
        for (final e in evidence) EntryDraft(evidencePath: e.file.path),
      ],
      isReading: true,
    );

    final capture = ref.read(captureServiceProvider);
    final ocr = ref.read(ocrServiceProvider);
    final sheets = ref.read(sheetsRepositoryProvider);
    // 추천을 위해 시트를 읽어야 한다. 인가가 없으면 OCR 만 하고 넘어간다.
    final client = await ref.read(googleAuthProvider).authorizedClient(
          interactive: false,
        );

    final out = <EntryDraft>[];
    for (var i = 0; i < evidence.length; i++) {
      var draft = state.drafts[i];
      final e = evidence[i];

      // PDF 는 이미지가 아니라 OCR 로 못 보낸다. 사용자가 직접 채운다.
      if (e.isImage) {
        try {
          final bytes = await capture.compressForOcr(e.file);
          final r = await ocr.extract(imageBytes: bytes);
          draft = draft.copyWith(
            belongDate: r.belongDate,
            spendDate: r.belongDate,
            vendor: r.vendor,
            description: r.description,
            totalAmount: r.totalAmount,
            supplyAmount: r.supplyAmount,
            vatAmount: r.vatAmount,
            vatPrinted: r.vatPrinted,
            cardLast4: r.cardLast4,
          );
        } on Object catch (err) {
          // 한 장이 실패해도 나머지는 계속 읽는다. 사용자가 직접 채우면 된다.
          state = state.copyWith(error: '$err');
        }
      }

      // ── 자동완성의 실제 승부처: 과거에 같은 업체를 어떻게 처리했는가 ──
      final vendor = draft.vendor;
      if (client != null && vendor != null && vendor.isNotEmpty) {
        try {
          final s = await sheets.suggestForVendor(
            client: client,
            vendor: vendor,
          );
          if (s != null) {
            draft = draft.copyWith(
              expenseCategory: s.expenseCategory,
              classCode: s.classCode,
              className: s.className,
              // 근거 없이 채워두면 사용자가 못 믿고 전부 다시 확인한다.
              suggestionReason: '$vendor는 지난 ${s.reason}',
            );
          }
        } on Object {
          // 추천은 실패해도 진행에 지장 없다. 사용자가 직접 고르면 된다.
        }
      }

      out.add(draft);
    }

    state = state.copyWith(drafts: out, isReading: false);
  }

  void select(int index) => state = state.copyWith(selected: index);

  /// 지금 보고 있는 건을 수정한다.
  void update(EntryDraft Function(EntryDraft) edit) {
    final i = state.selected;
    if (i >= state.drafts.length) return;
    final next = <EntryDraft>[...state.drafts];
    next[i] = edit(next[i]);
    state = state.copyWith(drafts: next, clearError: true);
  }

  /// 총액을 1.1로 나눈다. **사용자가 눌렀을 때만** 부른다 —
  /// 면세(도서 등)는 부가세가 0원이라 자동으로 하면 틀린다.
  void applyVatSplit() {
    update((d) {
      final total = d.totalAmount;
      if (total == null) return d;
      final r = splitVat(total);
      return d.copyWith(supplyAmount: r.supply, vatAmount: r.vat, vatPrinted: true);
    });
  }

  /// 전부 큐에 넣는다. **전송은 하지 않는다** — 사용자가 [전송 시도] 를 눌러야 나간다.
  Future<int> enqueueAll() async {
    final account = ref.read(authControllerProvider).value;
    final email = account?.email;
    if (email == null) throw StateError('로그인이 필요합니다.');

    final db = ref.read(queueDbProvider);
    var count = 0;
    for (final d in state.drafts) {
      final entry = d.toEntry(createdBy: email);
      await db.enqueue(
        SubmissionsCompanion.insert(
          localId: _uuid.v4(),
          entryKind: Value(EntryKind.purchase.wireName),
          entryJson: jsonEncode(entry.toJson()),
          evidencePath: d.evidencePath,
          filename: d.filename,
          createdAt: DateTime.now(),
          driveUrl: const Value(null),
        ),
      );
      count++;
    }
    state = const ReviewState();
    return count;
  }
}

final reviewControllerProvider =
    NotifierProvider<ReviewController, ReviewState>(ReviewController.new);
