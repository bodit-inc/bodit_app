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
    this.isSubmitting = false,
    this.editingId,
    this.error,
  });

  final List<EntryDraft> drafts;

  /// 여러 건일 때 지금 보고 있는 건.
  final int selected;

  /// OCR 진행 중 (시안 ④).
  final bool isReading;

  /// 제출 후 전송 시도 중.
  final bool isSubmitting;

  /// 전송 대기 중인 건을 고치는 중이면 그 큐 행의 id.
  /// null 이면 새 건이다.
  final int? editingId;

  bool get isEditing => editingId != null;

  /// 예외 **원문**. 사람이 읽을 문구는 화면이 붙인다
  /// (`ErrorDisclosure` 가 한 줄 + 접힌 원문으로 보여준다).
  final String? error;

  EntryDraft? get current => selected < drafts.length ? drafts[selected] : null;

  bool get isMulti => drafts.length > 1;

  /// 모든 건이 제출 가능한 상태인지.
  bool get allComplete =>
      drafts.isNotEmpty && drafts.every((d) => d.isComplete);

  ReviewState copyWith({
    List<EntryDraft>? drafts,
    int? selected,
    bool? isReading,
    bool? isSubmitting,
    int? editingId,
    String? error,
    bool clearError = false,
  }) {
    return ReviewState(
      drafts: drafts ?? this.drafts,
      selected: selected ?? this.selected,
      isReading: isReading ?? this.isReading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      editingId: editingId ?? this.editingId,
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
    final client = await ref
        .read(googleAuthProvider)
        .authorizedClient(interactive: false);

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
              // 내역은 채우지 않고 후보로만 넘긴다(위 주석 참조).
              descriptionSuggestions: s.recentDescriptions,
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

  /// 전송 대기 중인 건을 다시 연다. OCR 은 돌리지 않는다 — 이미 확정된 값이다.
  ///
  /// **아직 아무 목적지에도 안 나간 건만** 부른다. Drive 에 이미 올라간 건을
  /// 고치면 파일명과 시트 행이 어긋난다(호출부에서 막는다).
  void loadForEdit(Submission row) {
    final entry = PurchaseEntry.fromJson(
      jsonDecode(row.entryJson) as Map<String, dynamic>,
    );
    state = ReviewState(
      drafts: <EntryDraft>[
        EntryDraft.fromEntry(
          entry,
          evidencePath: row.evidencePath,
          filename: row.filename,
        ),
      ],
      editingId: row.id,
    );
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
      return d.copyWith(
        supplyAmount: r.supply,
        vatAmount: r.vat,
        vatPrinted: true,
      );
    });
  }

  /// 저장하고 **바로 전송을 시도한다.** 실패한 건만 전송 대기에 남는다.
  ///
  /// ## 순서가 중요하다: 큐에 먼저 넣고, 그다음 보낸다
  ///
  /// 전송부터 하고 실패했을 때 큐에 넣으면, 전송 도중 앱이 죽거나 강제 종료될 때
  /// **건이 통째로 사라진다.** 사용자는 증빙을 다시 찍어야 한다.
  ///
  /// 먼저 큐에 넣으면 최악의 경우에도 "전송 대기" 로 남는다. 다시 켜서
  /// [전송 시도] 를 누르면 된다. 큐 쓰기는 로컬이라 거의 실패하지 않는다.
  ///
  /// ## 재전송은 여전히 수동이다 (ADR 12a)
  ///
  /// 바뀐 건 **첫 시도를 자동으로 한다**는 것뿐이다. 실패한 건을 앱이 알아서
  /// 다시 보내지 않는다 — 백그라운드 워커도 connectivity 리스너도 없다.
  Future<SubmitSummary> submitAll() async {
    final account = ref.read(authControllerProvider).value;
    final email = account?.email;
    if (email == null) throw StateError('로그인이 필요합니다.');

    final db = ref.read(queueDbProvider);
    final ids = <int>[];

    // ── 편집이면 새로 넣지 않고 그 행을 고친다 ────────────────────
    //    새로 넣으면 같은 증빙이 큐에 두 건이 된다.
    final editingId = state.editingId;
    if (editingId != null) {
      final row = await db.byId(editingId);
      if (row == null) throw StateError('고치려던 건을 찾을 수 없습니다.');
      final d = state.drafts.first;
      await db.updateRow(
        row.copyWith(
          entryJson: jsonEncode(d.toEntry(createdBy: email).toJson()),
          filename: d.filename,
          // 다시 보낼 것이므로 지난 실패 사유는 지운다.
          lastError: const Value(null),
        ),
      );
      ids.add(editingId);
    }

    // ── 1. 새 건은 전부 큐에 넣는다 (유실 방지) ───────────────────
    for (final d in editingId != null ? <EntryDraft>[] : state.drafts) {
      final entry = d.toEntry(createdBy: email);
      final id = await db.enqueue(
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
      ids.add(id);
    }

    // ── 2. 방금 넣은 것만 바로 보낸다 ──────────────────────────────
    //    sendPending() 이 아니라 id 를 짚어 보낸다 — 예전에 실패해 쌓여 있던
    //    건까지 같이 나가면 사용자가 방금 낸 것의 결과를 알 수 없다.
    state = state.copyWith(isSubmitting: true);
    final sender = ref.read(submissionSenderProvider);
    var sent = 0;
    String? firstError;

    for (final id in ids) {
      final row = await db.byId(id);
      if (row == null) continue;
      final outcome = await sender.sendOne(row);
      if (outcome.allDone) {
        sent++;
      } else {
        firstError ??= outcome.error;
      }
    }

    state = const ReviewState();
    return SubmitSummary(total: ids.length, sent: sent, firstError: firstError);
  }
}

/// 제출 결과. 화면이 이걸로 문구를 만든다.
class SubmitSummary {
  const SubmitSummary({
    required this.total,
    required this.sent,
    this.firstError,
  });

  final int total;

  /// 세 목적지 전부 성공한 건수.
  final int sent;

  /// 실패가 있었다면 첫 사유. 조용히 넘기지 않는다.
  final String? firstError;

  int get failed => total - sent;
  bool get allSent => failed == 0;
}

final reviewControllerProvider =
    NotifierProvider<ReviewController, ReviewState>(ReviewController.new);
