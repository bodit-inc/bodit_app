/// 검토 화면의 상태. 촬영 → OCR → 추천 → 확인 → 큐 적재까지를 들고 있다.
///
/// 여러 장을 한 번에 다루므로 draft 를 **목록**으로 갖는다(시안 ⑥).
/// 한 장이면 목록 길이가 1일 뿐, 코드 경로는 같다.
library;

import 'dart:convert';

import 'package:bodit_app/core/log.dart';
import 'package:bodit_app/data/local/queue_db.dart';
import 'package:bodit_app/data/providers.dart';
import 'package:bodit_app/data/remote/card_repository.dart';
import 'package:bodit_app/features/auth/auth_controller.dart';
import 'package:bodit_app/features/capture/capture_service.dart';
import 'package:bodit_app/models/class_choice.dart';
import 'package:bodit_app/models/entry_draft.dart';
import 'package:bodit_app/models/purchase_entry.dart';
import 'package:bodit_app/models/sheet_row.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:googleapis_auth/googleapis_auth.dart' as gapis;
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

  /// 뒤 4자리 → 카드. 분류를 정하는 근거다.
  ///
  /// 컨트롤러가 들고 있는 이유: 사용자가 **카드번호를 고치면 분류를 다시 정해야**
  /// 하는데, 그때마다 시트를 다시 읽을 수는 없다. 한 번 읽어 세션 동안 쓴다.
  CardDirectory? _cards;

  /// 분류코드 → 분류명. **분류명의 출처는 여기 하나다** —
  /// 카드 시트에도 분류명 칸이 있지만 두 시트가 어긋난 적이 있어서 안 읽는다
  /// (`card_repository.dart` 주석 참조).
  Map<int, String>? _classNames;

  /// 카드·분류 마스터를 읽어둔다. **실패해도 던지지 않는다** —
  /// 분류 자동완성이 안 될 뿐 폼은 그대로 쓸 수 있다. 다만 왜 비었는지는
  /// `cardNotice` 로 화면에 남는다.
  Future<void> _loadCardData(gapis.AuthClient client) async {
    if (_cards != null && _classNames != null) return;
    try {
      _cards ??= await ref.read(cardRepositoryProvider).load(client);
    } on Object catch (e) {
      log.w('카드보유내역을 읽지 못했다 (분류 자동완성을 건너뛴다): $e');
    }
    try {
      _classNames ??= await ref
          .read(masterDataRepositoryProvider)
          .classNames(client);
    } on Object catch (e) {
      log.w('분류 마스터를 읽지 못했다 (분류 자동완성을 건너뛴다): $e');
    }
  }

  /// 카드 뒤 4자리로 분류를 정한다. **분류가 자동으로 채워지는 유일한 경로다.**
  ///
  /// 못 정하는 경우가 네 가지인데 **전부 다른 문구로 알린다.** 뭉뚱그려
  /// "분류를 찾지 못했습니다" 라고 하면 사용자가 뭘 해야 할지 모른다 —
  /// 카드번호를 고쳐야 하는지, 시트에 카드를 추가해야 하는지, 그냥 직접
  /// 고르면 되는지가 다 다르다.
  /// 인스턴스가 들고 있는 카드·마스터로 판단한다. 실제 로직은 [applyCardClass].
  EntryDraft _applyCardClass(EntryDraft draft) =>
      applyCardClass(draft, _cards, _classNames);

  /// [_applyCardClass] 의 알맹이. **상태에 기대지 않는 순수 함수다** —
  /// 경우가 다섯 가지(정상·못 찾음·미사용·겹침·마스터 누락)라 전부 테스트한다.
  @visibleForTesting
  static EntryDraft applyCardClass(
    EntryDraft draft,
    CardDirectory? cards,
    Map<int, String>? classNames,
  ) {
    // 지난 판단의 흔적을 먼저 지운다. 카드번호를 고쳤는데 예전 근거가 남아
    // 있으면 사용자는 새 번호가 반영된 줄 안다.
    //
    // **분류코드까지 지울지는 출처를 보고 정한다.** `classReason` 이 있으면
    // 그 값은 카드가 채운 것이다 — 카드가 바뀌었으니 같이 내려가야 한다.
    // 반대로 사용자가 46개 목록에서 직접 고른 값은 건드리지 않는다
    // (그쪽은 고를 때 `classReason` 을 지워서 출처를 표시해둔다).
    final fromCard = draft.classReason != null;
    final d = draft.copyWith(
      classReason: null,
      cardNotice: null,
      classSuggestions: const <ClassChoice>[],
      classCode: fromCard ? null : draft.classCode,
      className: fromCard ? null : draft.className,
    );

    final last4 = (d.cardLast4 ?? '').trim();
    // 카드가 없는 증빙이다(계산서·이체확인증·현금영수증). 할 말이 없다 —
    // 여기서 배너를 띄우면 이체 건마다 쓸데없는 경고가 뜬다.
    if (last4.isEmpty) return d;

    if (cards == null || classNames == null) {
      return d.copyWith(
        cardNotice:
            '카드 정보를 불러오지 못해 분류를 자동으로 채우지 못했습니다. '
            '분류를 직접 골라주세요.',
      );
    }

    final hits = cards.find(last4);
    final active = hits.where((c) => c.active).toList();
    if (active.isEmpty) {
      return d.copyWith(
        cardNotice: hits.isEmpty
            ? '카드 $last4 를 카드보유내역에서 찾지 못했습니다. '
                  '번호가 맞는지 확인하고 분류를 직접 골라주세요.'
            : '카드 $last4 는 지금 사용하지 않는 카드로 등록돼 있습니다. '
                  '분류를 직접 골라주세요.',
      );
    }

    // 분류명을 못 푸는 코드는 후보에서 뺀다 — 이름 없이 코드만 시트에 넣으면
    // 회계 담당자가 보는 분류명 칸이 빈다.
    final choices = <ClassChoice>[];
    final unresolved = <int>[];
    for (final c in active) {
      final r = resolveClass(c, classNames);
      if (r == null) {
        unresolved.add(c.classCode);
      } else if (!choices.contains(r)) {
        choices.add(r);
      }
    }

    if (unresolved.isNotEmpty) {
      // 마스터가 낡았다는 뜻이다. 자동으로 채우면 틀린 예산에 잡히므로 멈춘다.
      return d.copyWith(
        classSuggestions: choices,
        cardNotice:
            '카드 $last4 의 분류코드 ${unresolved.join(', ')} 가 분류 마스터에 없습니다. '
            '`_분류마스터` 탭을 확인하고, 지금은 분류를 직접 골라주세요.',
      );
    }

    if (choices.length == 1) {
      final only = choices.single;
      return d.copyWith(
        classCode: only.code,
        className: only.name,
        // 근거를 안 보여주면 사용자가 못 믿고 46개 목록을 다시 연다.
        classReason: '카드 $last4 · ${only.name}',
      );
    }

    // 뒤 4자리가 겹친다. **조용히 첫 번째를 고르지 않는다** —
    // 겹치는 순간부터 절반이 틀린 예산에 잡힌다.
    return d.copyWith(
      classSuggestions: choices,
      cardNotice:
          '뒤 4자리가 $last4 인 카드가 ${choices.length}장입니다. '
          '어느 쪽인지 골라주세요.',
    );
  }

  /// 사용자가 카드 뒤 4자리를 고쳤다. **분류를 다시 정한다.**
  ///
  /// OCR 이 숫자 하나를 잘못 읽으면 분류가 통째로 틀리는데, 고쳐도 분류가
  /// 그대로면 사용자는 고친 줄 안다.
  Future<void> setCardLast4(String raw) async {
    // 사용자가 전체 번호를 붙여넣을 수도 있다. 뒤 4자리만 남긴다 —
    // 앞자리는 저장하지 않는다(ADR: 카드번호는 뒤 4자리만).
    final last4 = CardDirectory.last4Of(raw) ?? '';
    update((d) => d.copyWith(cardLast4: last4));

    // 아직 못 읽었으면 지금 읽어본다. 사용자 조작 중이지만 동의 화면은
    // 띄우지 않는다 — 번호 하나 고치다가 팝업이 뜨면 흐름이 끊긴다.
    if (_cards == null || _classNames == null) {
      final client = await ref
          .read(googleAuthProvider)
          .authorizedClient(interactive: false);
      if (client != null) await _loadCardData(client);
    }
    update(_applyCardClass);
  }

  /// 뒤 4자리가 겹쳤을 때 사용자가 고른 분류.
  void chooseClass(ClassChoice choice) {
    update(
      (d) => d.copyWith(
        classCode: choice.code,
        className: choice.name,
        classReason: '카드 ${d.cardLast4 ?? ''} · ${choice.name} (직접 고름)',
        // 골랐으니 안내와 후보는 치운다. 남겨두면 아직 덜 된 것처럼 보인다.
        cardNotice: null,
        classSuggestions: const <ClassChoice>[],
      ),
    );
  }

  /// 증빙을 받아 draft 를 만들고 OCR 을 돌린다.
  Future<void> load(List<CapturedEvidence> evidence) async {
    if (evidence.isEmpty) return;

    state = ReviewState(
      drafts: <EntryDraft>[
        for (final e in evidence) EntryDraft(evidencePath: e.file.path),
      ],
      isReading: true,
    );

    // 카드 목록과 분류 마스터는 건마다 바뀌지 않는다. **루프 밖에서 한 번만**
    // 읽어 둔다 — 안에서 읽으면 10장 찍었을 때 시트를 20번 더 읽는다.
    // (`_readOne` 은 이미 읽혀 있으면 건너뛴다.)
    final client = await ref
        .read(googleAuthProvider)
        .authorizedClient(interactive: false);
    if (client != null) await _loadCardData(client);

    final out = <EntryDraft>[];
    for (var i = 0; i < evidence.length; i++) {
      out.add(await _readOne(evidence[i], state.drafts[i]));
    }

    state = state.copyWith(drafts: out, isReading: false);
  }

  /// 증빙 한 장을 읽어 draft 를 채운다. **읽기 경로는 여기 하나다** —
  /// 처음 불러올 때와 사진을 다시 찍었을 때가 같은 코드를 타야
  /// 한쪽만 고쳐지는 일이 없다.
  ///
  /// 카드·분류 마스터는 이미 읽혀 있다고 본다(`_loadCardData`). 여기서 읽으면
  /// 10장 찍었을 때 시트를 20번 더 읽는다.
  Future<EntryDraft> _readOne(CapturedEvidence e, EntryDraft initial) async {
    var draft = initial;
    final capture = ref.read(captureServiceProvider);
    final ocr = ref.read(ocrServiceProvider);
    final sheets = ref.read(sheetsRepositoryProvider);
    final client = await ref
        .read(googleAuthProvider)
        .authorizedClient(interactive: false);
    if (client != null) await _loadCardData(client);

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
          confidence: r.confidence,
          // 읽을 만한 사진이었으면 할 말이 없다. 멀쩡한 사진에 경고를 띄우면
          // 정작 흔들린 사진의 경고도 같이 무시된다.
          imageProblem: r.quality.readable ? null : r.quality.problem,
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
        final s = await sheets.suggestForVendor(client: client, vendor: vendor);
        if (s != null) {
          // **분류(classCode·className)는 여기서 채우지 않는다.**
          // 업체 이력은 추측이고 카드는 사실이다 — 같은 업체에서 같은 걸 사도
          // 어느 예산으로 긁었는지는 카드가 정한다. 분류는 _applyCardClass 담당.
          draft = draft.copyWith(
            expenseCategory: s.expenseCategory,
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

    // ── 분류는 카드가 정한다 ────────────────────────────────────────
    //    업체 이력보다 **뒤에** 둔다. 순서가 바뀌면 이력이 분류를 덮는다.
    return _applyCardClass(draft);
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

  /// 지금 보고 있는 건의 증빙을 새 사진으로 갈아끼우고 **다시 읽는다.**
  ///
  /// 흔들린 사진을 다시 찍었을 때 쓴다. 건을 새로 만들지 않는 이유:
  /// 못 쓸 사진이 목록에 남으면 사용자가 둘 중 뭘 제출할지 헷갈린다.
  ///
  /// 사용자가 손으로 고쳐둔 값도 같이 날아간다 — 새 사진에서 다시 읽는 게
  /// 맞다. 잘못 읽힌 값 위에 덧칠하면 어느 쪽이 새 값인지 알 수 없다.
  Future<void> replaceEvidence(CapturedEvidence evidence) async {
    final i = state.selected;
    if (i >= state.drafts.length) return;

    final kept = <EntryDraft>[...state.drafts];
    // 사용자가 직접 정한 파일명은 지키지 않는다 — 항목이 다시 읽히면
    // 자동 파일명도 달라지는데, 옛 이름만 남으면 둘이 어긋난다.
    kept[i] = EntryDraft(evidencePath: evidence.file.path);
    state = state.copyWith(drafts: kept, isReading: true, clearError: true);

    final draft = await _readOne(evidence, kept[i]);
    final next = <EntryDraft>[...state.drafts];
    next[i] = draft;
    state = state.copyWith(drafts: next, isReading: false);
  }

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
  ///
  /// 누른 사실을 [EntryDraft.vatSplitApplied] 에 남긴다. 나중에 총금액을
  /// 고칠 때 같은 판단을 다시 적용하기 위해서다([setTotalAmount]).
  void applyVatSplit() {
    update((d) {
      final total = d.totalAmount;
      if (total == null) return d;
      final r = splitVat(total);
      return d.copyWith(
        supplyAmount: r.supply,
        vatAmount: r.vat,
        vatPrinted: true,
        vatSplitApplied: true,
      );
    });
  }

  /// 총금액을 고친다. **공급가액·부가세를 그대로 두지 않는다.**
  ///
  /// 예전엔 총금액만 바뀌고 나머지는 옛 값이 남았다 —
  /// `총 11,000 / 공급 10,000 / 부가 1,000` 에서 총액만 22,000 으로 고치면
  /// 합이 안 맞는 행이 그대로 시트에 들어갔다.
  ///
  /// 그렇다고 **자동으로 1.1 을 나누면 안 된다.** 면세(도서 등)는 부가세가
  /// 0원이 맞아서, 자동 계산은 없는 세금을 만들어낸다. 그래서 갈라서 다룬다:
  ///
  ///   - 전에 [applyVatSplit] 을 눌렀으면 → 사용자가 이미 "과세" 라고
  ///     판단한 건이다. 같은 판단을 새 금액에 다시 적용한다
  ///   - 안 눌렀으면 → 비우고 다시 묻는다. `vatPrinted` 도 내려서
  ///     "1.1로 나누기" 안내가 다시 뜨게 한다
  void setTotalAmount(int total, {required String currencyCode}) {
    update((d) {
      // 통화를 바꿨으면 같이 반영한다 — 금액만 바꾸면 단위가 어긋난다.
      final next = d.copyWith(totalAmount: total, currency: currencyCode);
      if (d.vatSplitApplied) {
        final r = splitVat(total);
        return next.copyWith(supplyAmount: r.supply, vatAmount: r.vat);
      }
      // 애초에 비어 있었으면 건드릴 것이 없다.
      if (d.supplyAmount == null && d.vatAmount == null) return next;
      return next.copyWith(
        supplyAmount: null,
        vatAmount: null,
        vatPrinted: false,
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
