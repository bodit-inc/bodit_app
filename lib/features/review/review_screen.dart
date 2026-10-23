import 'dart:async';
import 'dart:io';

import 'package:bodit_app/core/theme/tokens.dart';
import 'package:bodit_app/core/utils/currency.dart';
import 'package:bodit_app/core/utils/filename.dart';
import 'package:bodit_app/core/utils/korean_amount.dart';
import 'package:bodit_app/core/widgets/amount_keypad.dart';
import 'package:bodit_app/core/widgets/app_widgets.dart';
import 'package:bodit_app/data/providers.dart';
import 'package:bodit_app/features/review/review_controller.dart';
import 'package:bodit_app/models/class_choice.dart';
import 'package:bodit_app/models/entry_draft.dart';
import 'package:bodit_app/models/evidence_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 시안 ④⑤⑥⑦⑧⑨ — 검토 폼.
///
/// 확신 낮은 필드를 표시하지 않는다(ADR Decision 11). 어차피 전부 훑어야 하는데
/// 특정 필드만 찍으면 나머지를 안 보게 된다. 대신 **비어 있는 칸**은 알려준다 —
/// 그건 확신의 문제가 아니라 제출이 막히는 문제다.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  /// 비어 있을 수 있는 칸들의 화면상 위치.
  ///
  /// 제출을 눌렀는데 덜 찼을 때 **그 칸으로 데려가려면** 필요하다.
  /// 키 이름은 `EntryDraft.missingFields` 가 내는 문자열과 같아야 한다 —
  /// 그래야 "무엇이 비었는지" 와 "어디로 갈지" 가 따로 놀지 않는다.
  final _fieldKeys = <String, GlobalKey>{
    '소속날짜': GlobalKey(),
    '업체명': GlobalKey(),
    '내역': GlobalKey(),
    '비목': GlobalKey(),
    '분류코드': GlobalKey(),
    '총금액': GlobalKey(),
  };

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reviewControllerProvider);

    // 시안 ④ — OCR 진행 중
    if (state.isReading) return const _ReadingView();

    final draft = state.current;
    if (draft == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('검토')),
        body: const Center(child: Text('증빙이 없습니다.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(state.isMulti ? '검토 · ${state.drafts.length}건' : '검토'),
        actions: [
          if (state.isSubmitting)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: Gap.lg),
              child: Center(
                child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            // 비어 있어도 **누를 수 있게** 둔다. 비활성 버튼은 왜 안 되는지
            // 말해주지 않아서, 사용자는 위쪽만 들여다보다 막힌다.
            // 누르면 첫 빈 칸으로 데려간다.
            TextButton(
              onPressed: () => _submit(context, ref),
              child: Text(state.isMulti ? '전체 제출' : '제출'),
            ),
        ],
      ),
      // 비어 있는 항목 바는 **스크롤 밖**에 둔다.
      //
      // pinned SliverAppBar 로도 항상 띄울 수 있지만, 그러면 스크롤하는 동안
      // 매 프레임 레이아웃 계산에 참여한다. 밖에 두면 한 번 배치되고 끝이고
      // 스크롤과 무관해진다. 코드도 슬리버 없이 단순해진다.
      //
      // 제출이 시작되면 화면을 잠근다(AbsorbPointer). 예전엔 전송 중에도 값을
      // 고칠 수 있어서, 이미 큐에 들어간 내용과 화면이 어긋났다 —
      // 사용자는 고쳐진 줄 안다.
      body: AbsorbPointer(
        absorbing: state.isSubmitting,
        child: Column(
          children: [
            if (draft.missingFields.isNotEmpty)
              _MissingFieldsBar(draft.missingFields),
            Expanded(
              child: ListView(
                padding: screenPadding,
                children: [
                  // 무엇을 올리는지 보고 확인해야 한다 — 값만 보고는 OCR 이 엉뚱한
                  // 영수증을 읽었는지 알 수 없다. 다건일 때는 특히 그렇다.
                  _EvidencePreview(draft.evidencePath),
                  // 흔들리거나 잘린 사진은 값이 틀린 채로 그럴듯하게 들어온다.
                  // 읽어본 쪽(모델)이 못 읽겠다고 하면 **다시 찍는 게 가장 싸다** —
                  // 여기서 안 잡으면 회계 담당자가 시트에서 발견한다.
                  if (draft.imageProblem != null) ...[
                    const SizedBox(height: Gap.md),
                    NoticeBanner(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(draft.imageProblem!),
                          const SizedBox(height: Gap.sm),
                          InlineButton(
                            onPressed: () => _retake(context, ref),
                            label: '다시 찍기',
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: Gap.md),

                  // 시안 ⑥ — 여러 건일 때 건별 목록
                  if (state.isMulti) ...[
                    SectionHeader('읽은 증빙 ${state.drafts.length}건'),
                    AppCard(
                      children: [
                        for (var i = 0; i < state.drafts.length; i++)
                          _DraftRow(
                            draft: state.drafts[i],
                            selected: i == state.selected,
                            onTap: () => ref
                                .read(reviewControllerProvider.notifier)
                                .select(i),
                          ),
                      ],
                    ),
                    const NoteText('한 건씩 눌러서 확인합니다. 전부 채우면 한 번에 제출됩니다.'),
                  ],

                  const SectionHeader('기본'),
                  AppCard(
                    children: [
                      // 두 날짜의 차이를 아무도 모른다. 이름만으로는 구분이 안 돼서
                      // 회계 담당자가 요구사항 문서에 적어둔 설명을 그대로 붙인다.
                      LabeledRow(
                        key: _fieldKeys['소속날짜'],
                        label: '소속날짜',
                        uncertain: draft.isUncertain('belong_date'),
                        value: _fmtDate(draft.belongDate),
                        placeholder: '입력 필요',
                        subtitle: '계산서 발행일자 또는 카드 결제일자',
                        onTap: () => _pickDate(context, ref, draft),
                      ),
                      LabeledRow(
                        label: '지출날짜',
                        value: _fmtDate(draft.spendDate ?? draft.belongDate),
                        placeholder: '소속날짜와 동일',
                        subtitle: '실제로 비용을 집행한 일자',
                        onTap: () {},
                      ),
                      LabeledRow(
                        key: _fieldKeys['업체명'],
                        label: '업체명',
                        uncertain: draft.isUncertain('vendor'),
                        editable: true,
                        value: draft.vendor,
                        placeholder: '입력 필요',
                        onTap: () => _editText(
                          context,
                          ref,
                          '업체명',
                          draft.vendor,
                          (d, v) => d.copyWith(vendor: v),
                        ),
                      ),
                      // 카드번호는 **분류를 정하는 입력**이다. 예전엔 OCR 이 읽은
                      // 값이 화면에 아예 안 나와서, 숫자 하나를 잘못 읽어도
                      // 사용자가 알 길이 없었다. 지금은 그게 분류까지 끌고 간다.
                      LabeledRow(
                        label: '카드번호',
                        uncertain: draft.isUncertain('card_last4'),
                        editable: true,
                        value: draft.cardLast4,
                        placeholder: '카드 결제가 아니면 비워둡니다',
                        onTap: () => _editCardLast4(context, ref, draft),
                      ),
                      // 내역은 OCR 이 읽은 품목명이 그대로 들어가 있기 쉬운데,
                      // 회계가 원하는 건 "무슨 건인지" 다. **직접 써야 하는 칸**이라는
                      // 신호를 주려고 안내를 경고색으로 띄운다.
                      LabeledRow(
                        key: _fieldKeys['내역'],
                        label: '내역',
                        uncertain: draft.isUncertain('description'),
                        editable: true,
                        value: draft.description,
                        placeholder: '직접 입력',
                        warnPlaceholder: true,
                        onTap: () => _editText(
                          context,
                          ref,
                          '내역',
                          draft.description,
                          (d, v) => d.copyWith(description: v),
                        ),
                      ),
                      // 같은 업체로 과거에 쓴 내역. **자동으로 안 채운다** —
                      // 내역은 건마다 달라서("8월 도서" → "9월 도서") 지난 값을
                      // 넣으면 9월에 8월 것이 조용히 들어간다. 눌러서 고른다.
                      if (draft.descriptionSuggestions.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            Gap.lg,
                            0,
                            Gap.lg,
                            Gap.md,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '이 업체로 전에 쓴 내역',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                              const SizedBox(height: Gap.sm),
                              Wrap(
                                spacing: Gap.sm,
                                runSpacing: Gap.sm,
                                children: [
                                  for (final d in draft.descriptionSuggestions)
                                    SuggestChip(
                                      d,
                                      selected: d == draft.description,
                                      onTap: () => ref
                                          .read(
                                            reviewControllerProvider.notifier,
                                          )
                                          .update(
                                            (x) => x.copyWith(description: d),
                                          ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  // 모르면 지어내는 것보다 비워두는 게 낫다 — 그 사실을 알려야
                  // 사용자가 아무 말이나 채워 넣지 않는다.
                  const NoteText('내역을 모르면 비워두세요. "$needsOpsReview" 으로 제출됩니다.'),

                  // 시안 ⑦ — 영수증에 없는 항목은 과거 이력으로 추천
                  const SectionHeader('분류 — 영수증에 없는 항목'),
                  AppCard(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(Gap.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '비목',
                              key: _fieldKeys['비목'],
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: Gap.sm),
                            Wrap(
                              spacing: Gap.sm,
                              runSpacing: Gap.sm,
                              children: [
                                if (draft.expenseCategory != null)
                                  SuggestChip(
                                    draft.expenseCategory!,
                                    selected: true,
                                    onTap: () => _pickCategory(context, ref),
                                  ),
                                SuggestChip(
                                  draft.expenseCategory == null
                                      ? '선택하기'
                                      : '바꾸기',
                                  onTap: () => _pickCategory(context, ref),
                                ),
                              ],
                            ),
                            // 근거 없이 채워두면 사용자가 못 믿고 전부 다시 확인한다.
                            if (draft.suggestionReason != null)
                              SuggestReason(draft.suggestionReason!),

                            const SizedBox(height: Gap.lg),
                            Text(
                              '분류',
                              key: _fieldKeys['분류코드'],
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: Gap.sm),
                            // 분류코드와 분류명은 따로 받지 않는다 — 마스터에서 하나를
                            // 고르면 둘 다 정해진다. 코드를 손으로 치게 하면 마스터에
                            // 없는 번호가 들어가고, 그러면 시트의 분류명이 빈다.
                            Wrap(
                              spacing: Gap.sm,
                              runSpacing: Gap.sm,
                              children: [
                                if (draft.classCode != null)
                                  SuggestChip(
                                    '${draft.classCode} ${draft.className ?? ''}'
                                        .trim(),
                                    selected: true,
                                    onTap: () => _pickClass(context, ref),
                                  ),
                                SuggestChip(
                                  draft.classCode == null ? '선택하기' : '바꾸기',
                                  onTap: () => _pickClass(context, ref),
                                ),
                              ],
                            ),
                            // 카드로 정해진 분류의 근거. 비목과 줄을 따로 쓴다 —
                            // 비목은 과거 이력(추측), 분류는 카드(사실)라 출처가
                            // 다르다. 한 줄에 합치면 그 차이가 안 보인다.
                            if (draft.classReason != null)
                              SuggestReason(draft.classReason!),

                            // 뒤 4자리가 겹쳤을 때의 후보. **자동으로 안 고른다** —
                            // 조용히 첫 번째를 쓰면 절반이 틀린 예산에 잡힌다.
                            if (draft.classSuggestions.isNotEmpty) ...[
                              const SizedBox(height: Gap.sm),
                              Wrap(
                                spacing: Gap.sm,
                                runSpacing: Gap.sm,
                                children: [
                                  for (final c in draft.classSuggestions)
                                    SuggestChip(
                                      c.label,
                                      selected: c.code == draft.classCode,
                                      onTap: () => ref
                                          .read(
                                            reviewControllerProvider.notifier,
                                          )
                                          .chooseClass(c),
                                    ),
                                ],
                              ),
                            ],

                            // 카드로 분류를 못 정했으면 **왜** 못 정했는지 말한다.
                            // 조용히 비워두면 사용자는 46개 목록에서 직접 찾는다.
                            if (draft.cardNotice != null) ...[
                              const SizedBox(height: Gap.md),
                              NoticeBanner(child: Text(draft.cardNotice!)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SectionHeader('금액'),
                  AppCard(
                    children: [
                      LabeledRow(
                        key: _fieldKeys['총금액'],
                        label: '총금액',
                        uncertain: draft.isUncertain('total_amount'),
                        editable: true,
                        value: _fmtAmount(draft.totalAmount, draft.currency),
                        placeholder: '입력 필요',
                        // 0 하나 틀리면 10배다. 숫자 옆에 한글로 같이 보여준다.
                        // **원화일 때만** — 외화를 한글로 읽으면 오히려 헷갈린다.
                        subtitle: _koreanOrNull(
                          draft.totalAmount,
                          draft.currency,
                        ),
                        // 총금액은 혼자 바뀌지 않는다 — 공급가액·부가세가
                        // 따라와야 한다. 그 규칙은 컨트롤러가 갖는다.
                        onTap: () => _editTotalAmount(context, ref, draft),
                      ),
                      LabeledRow(
                        label: '공급가액',
                        value: _fmtAmount(draft.supplyAmount, draft.currency),
                        placeholder: '총금액과 동일',
                        subtitle: _koreanOrNull(
                          draft.supplyAmount,
                          draft.currency,
                        ),
                      ),
                      LabeledRow(
                        label: '부가세',
                        value: _fmtAmount(draft.vatAmount ?? 0, draft.currency),
                        subtitle: _koreanOrNull(
                          draft.vatAmount ?? 0,
                          draft.currency,
                        ),
                      ),
                    ],
                  ),
                  // 부가세를 자동 계산하지 않는다 — 면세(도서 등)는 0원이 맞다.
                  if (!draft.vatPrinted && draft.totalAmount != null) ...[
                    const SizedBox(height: Gap.md),
                    NoticeBanner(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '영수증에 부가세가 인쇄돼 있지 않습니다.\n'
                            '면세 품목이면 0원이 맞습니다. 과세인데 총액만 찍혀 있다면 '
                            '아래로 나눌 수 있습니다.',
                          ),
                          const SizedBox(height: Gap.sm),
                          InlineButton(
                            onPressed: () => ref
                                .read(reviewControllerProvider.notifier)
                                .applyVatSplit(),
                            label: '1.1로 나누기',
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SectionHeader('저장될 파일명'),
                  AppCard(
                    children: [
                      // 파일명 네 번째 칸이 이 값이다. 예전엔 '영수증' 고정이라
                      // 매출전표를 올려도 파일명에 '영수증' 이 박혔다.
                      LabeledRow(
                        label: '증빙자료명',
                        value: draft.evidenceType,
                        onTap: () => _pickEvidenceType(context, ref),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(Gap.lg),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                draft.filename,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(fontFamily: 'monospace'),
                              ),
                            ),
                            TextButton(
                              onPressed: () =>
                                  _editFilename(context, ref, draft),
                              child: const Text('수정'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const NoteText('위 항목을 고치면 파일명도 따라 바뀝니다. 직접 고칠 수도 있습니다.'),

                  // OCR 이 실패해도 폼은 그대로 쓴다(직접 채우면 된다). 다만 왜 비었는지는
                  // 알려줘야 한다 — 지금까지 이 값이 화면에 안 나와서 조용히 삼켜졌다.
                  if (state.error != null) ...[
                    const SizedBox(height: Gap.lg),
                    ErrorDisclosure(
                      '증빙에서 항목을 읽지 못했습니다. 직접 채워주세요.',
                      detail: state.error!,
                    ),
                  ],
                  const SizedBox(height: Gap.xl),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 제출. 덜 찼으면 보내지 않고 **첫 빈 칸으로 데려간다.**
  Future<void> _submit(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final state = ref.read(reviewControllerProvider);

    if (!state.allComplete) {
      await _goToFirstMissing(state);
      return;
    }

    final navigator = Navigator.of(context);
    try {
      // 저장하고 바로 보낸다. 실패한 건만 전송 대기에 남는다.
      final r = await ref.read(reviewControllerProvider.notifier).submitAll();
      navigator.pop();

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            r.allSent
                ? '${r.sent}건을 전송했습니다.'
                : r.sent > 0
                ? '${r.sent}건 전송, ${r.failed}건은 전송 대기로 넘겼습니다.'
                : '전송하지 못해 전송 대기로 넘겼습니다.',
          ),
          // 실패했으면 사유를 볼 수 있어야 한다 — 조용히 넘기지 않는다.
          action: r.firstError == null
              ? null
              : SnackBarAction(
                  label: '사유 보기',
                  onPressed: () => showDetailDialog(
                    navigator.context,
                    title: '전송 실패',
                    detail: r.firstError!,
                  ),
                ),
          duration: const Duration(seconds: 6),
        ),
      );
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  /// 덜 채운 건으로 옮기고, 그 건의 첫 빈 칸을 화면에 띄운다.
  Future<void> _goToFirstMissing(ReviewState state) async {
    final messenger = ScaffoldMessenger.of(context);

    // 다건이면 덜 채운 건을 먼저 띄운다 — 보고 있는 건은 다 찼는데
    // 다른 건이 비어 있을 수 있다.
    final index = state.drafts.indexWhere((d) => !d.isComplete);
    if (index < 0) return;
    if (index != state.selected) {
      ref.read(reviewControllerProvider.notifier).select(index);
      // 화면이 그 건으로 다시 그려진 뒤에야 키가 제자리를 가리킨다.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }

    final field = state.drafts[index].missingFields.first;
    // GlobalKey 가 가리키는 건 이 State 가 아니라 그 칸의 엘리먼트다.
    // 위에서 건을 바꿨다면 그 사이 사라졌을 수 있으니 따로 확인한다.
    final ctx = _fieldKeys[field]?.currentContext;
    if (ctx != null && ctx.mounted) {
      await Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        // 화면 맨 위에 딱 붙이면 떠 있는 안내 바에 가린다. 조금 내려서 띄운다.
        alignment: 0.25,
      );
    }
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          state.isMulti
              ? '${index + 1}번째 건의 $field 을(를) 채워주세요.'
              : '$field 을(를) 채워주세요.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _pickCategory(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _CategoryPickerSheet(),
    );
  }

  Future<void> _pickClass(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _ClassPickerSheet(),
    );
  }

  /// 사진을 다시 찍어 지금 보고 있는 건을 교체한다.
  ///
  /// **건을 새로 만들지 않는다.** 새로 만들면 못 쓸 사진이 목록에 남고,
  /// 사용자가 둘 중 뭘 제출해야 하는지 헷갈린다.
  Future<void> _retake(BuildContext context, WidgetRef ref) async {
    final shot = await ref.read(captureServiceProvider).fromCamera();
    if (shot == null) return;
    await ref.read(reviewControllerProvider.notifier).replaceEvidence(shot);
  }

  Future<void> _pickEvidenceType(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _EvidenceTypePickerSheet(),
    );
  }

  /// 카드 뒤 4자리를 고친다. **고치면 분류가 다시 정해진다** —
  /// 컨트롤러가 그 일까지 맡으므로 여기서는 값만 넘긴다.
  Future<void> _editCardLast4(
    BuildContext context,
    WidgetRef ref,
    EntryDraft draft,
  ) async {
    final v = await promptText(
      context,
      title: '카드 뒤 4자리',
      initial: draft.cardLast4 ?? '',
      hintText: '예: 3927 · 카드 결제가 아니면 비워둡니다',
      keyboardType: TextInputType.number,
    );
    if (v == null) return;
    await ref.read(reviewControllerProvider.notifier).setCardLast4(v);
  }

  Future<void> _pickDate(
    BuildContext context,
    WidgetRef ref,
    EntryDraft draft,
  ) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: draft.belongDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    ref
        .read(reviewControllerProvider.notifier)
        .update((d) => d.copyWith(belongDate: picked));
  }

  Future<void> _editText(
    BuildContext context,
    WidgetRef ref,
    String label,
    String? initial,
    EntryDraft Function(EntryDraft, String) apply,
  ) async {
    final v = await promptText(context, title: label, initial: initial ?? '');
    if (v == null) return;
    ref.read(reviewControllerProvider.notifier).update((d) => apply(d, v));
  }

  /// 금액은 전용 키패드로 받는다. 시스템 키보드는 기기·IME 마다 배열이 달라
  /// 오입력이 나고, 한글 자판이나 소수점이 섞여 들어온다.
  /// 총금액 전용. 공급가액·부가세를 같이 정리한다
  /// (`ReviewController.setTotalAmount` 주석 참조).
  Future<void> _editTotalAmount(
    BuildContext context,
    WidgetRef ref,
    EntryDraft draft,
  ) async {
    final r = await showAmountKeypad(
      context,
      title: '총금액',
      initial: draft.totalAmount,
      currencyCode: draft.currency,
    );
    if (r == null) return;
    ref
        .read(reviewControllerProvider.notifier)
        .setTotalAmount(r.minor, currencyCode: r.currencyCode);
  }

  Future<void> _editFilename(
    BuildContext context,
    WidgetRef ref,
    EntryDraft draft,
  ) async {
    final v = await promptText(
      context,
      title: '파일명 수정',
      initial: draft.filename,
      maxLines: 2,
    );
    if (v == null) return;
    // 사용자가 직접 친 값에도 치환 규칙을 적용한다 — `/` 하나로 Drive 동기화가 깨진다.
    ref
        .read(reviewControllerProvider.notifier)
        .update((d) => d.copyWith(filenameOverride: sanitizeSegment(v)));
  }

  static String? _fmtDate(DateTime? d) => d == null
      ? null
      : '${d.year}-${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')}';

  static String? _fmtAmount(int? v, String code) =>
      v == null ? null : currencyOf(code).formatWithCode(v);

  /// 한글 풀이는 **원화일 때만** 붙인다.
  static String? _koreanOrNull(int? v, String code) =>
      (v == null || code != 'KRW') ? null : readKoreanAmount(v);
}

/// 시안 ④ — OCR 진행 중.
class _ReadingView extends StatelessWidget {
  const _ReadingView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('분석 중')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: Gap.lg),
            const Text('영수증을 읽는 중…'),
            const SizedBox(height: Gap.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.xxl),
              child: Text(
                '비목과 분류는 영수증에 없습니다.\n'
                '비목은 과거에 같은 업체를 어떻게 처리했는지 보고,\n'
                '분류는 결제한 카드를 보고 채웁니다.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AppColors.neutralFg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DraftRow extends StatelessWidget {
  const _DraftRow({
    required this.draft,
    required this.selected,
    required this.onTap,
  });

  final EntryDraft draft;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LabeledRow(
      label: '',
      value: draft.vendor ?? '(업체명 없음)',
      trailing: StatusPill(
        draft.isComplete ? '확인됨' : '확인 전',
        tone: draft.isComplete ? PillTone.ok : PillTone.waiting,
      ),
      onTap: onTap,
    );
  }
}

/// 시안 ⑧ — 비목 선택. 마스터는 **시트에서 읽는다**(하드코딩 금지).
///
/// 생김새는 분류 선택과 같다 — 둘 다 `PickerSheet` 다. 같은 일을 하는 화면이
/// 둘로 갈라져 있어서 분류에만 검색이 있었다.
class _CategoryPickerSheet extends ConsumerWidget {
  const _CategoryPickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(expenseCategoriesProvider);
    final current = ref
        .watch(reviewControllerProvider)
        .current
        ?.expenseCategory;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      builder: (_, controller) => categories.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: screenPadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ErrorDisclosure('비목을 불러오지 못했습니다.', detail: '$e'),
                const SizedBox(height: Gap.lg),
                // 시트를 닫았다 열어도 다시 읽지만(autoDispose),
                // 여기서 바로 눌러 재시도할 수 있으면 설정을 고치고
                // 확인하는 왕복이 짧아진다.
                RetryButton(
                  onPressed: () => ref.invalidate(expenseCategoriesProvider),
                ),
              ],
            ),
          ),
        ),
        // 빈 목록은 provider 가 이미 걸러서 던진다(탭이 비었다고 알려준다).
        data: (list) {
          // 시트에 적힌 순서는 사람이 추가한 순서라 규칙이 없다.
          // 33개를 눈으로 훑어야 하므로 가나다로 세운다.
          final sorted = [...list]..sort(compareKorean);
          return PickerSheet(
            title: '비목 선택',
            searchHint: '이름으로 검색 (예: 도서, 여비)',
            selectedLabel: current,
            items: [for (final name in sorted) PickerItem(label: name)],
            onSelected: (item) {
              ref
                  .read(reviewControllerProvider.notifier)
                  .update((d) => d.copyWith(expenseCategory: item.label));
              Navigator.pop(context);
            },
          );
        },
      ),
    );
  }
}

/// 증빙자료명 선택.
///
/// 비목·분류와 달리 **목록이 코드에 있다.** 시트에서 읽지 않는 이유는
/// `models/evidence_type.dart` 주석에 적어뒀다 — 요구사항 문서의 고정 목록이고
/// 늘어나려면 회계 처리 방식 자체가 바뀌어야 한다.
class _EvidenceTypePickerSheet extends ConsumerWidget {
  const _EvidenceTypePickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(reviewControllerProvider).current?.evidenceType;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (_, controller) => PickerSheet(
        title: '증빙자료명',
        searchHint: '이름으로 검색 (예: 전표, 계산서)',
        selectedLabel: current,
        // 가나다로 세우지 않는다 — 흔한 것부터가 찾기 빠르다.
        items: [for (final name in evidenceTypes) PickerItem(label: name)],
        onSelected: (item) {
          ref
              .read(reviewControllerProvider.notifier)
              .update((d) => d.copyWith(evidenceType: item.label));
          Navigator.pop(context);
        },
      ),
    );
  }
}

/// 분류 선택. `_분류마스터` 탭을 읽어 `코드 이름` 으로 보여준다.
///
/// 고르면 **분류코드와 분류명이 한 번에** 정해진다. 코드를 손으로 치게 하면
/// 마스터에 없는 번호가 들어갈 수 있고, 그러면 시트의 분류명 칸이 빈다
/// (시트에 수식을 안 두므로 앱이 채우는 유일한 경로다).
class _ClassPickerSheet extends ConsumerWidget {
  const _ClassPickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final names = ref.watch(classNamesProvider);
    final current = ref.watch(reviewControllerProvider).current?.className;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      builder: (_, controller) => names.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: screenPadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ErrorDisclosure('분류를 불러오지 못했습니다.', detail: '$e'),
                const SizedBox(height: Gap.lg),
                RetryButton(
                  onPressed: () => ref.invalidate(classNamesProvider),
                ),
              ],
            ),
          ),
        ),
        data: (map) {
          // 분류는 가나다가 아니라 **코드 순**이다. 회계 담당자가 번호로
          // 말하고, 번호가 사업 시작 순서라 관련된 것끼리 붙어 있다.
          final codes = map.keys.toList()..sort();
          return PickerSheet(
            title: '분류 선택',
            searchHint: '코드나 이름으로 검색 (예: 23, CTS)',
            selectedLabel: current,
            items: [
              for (final code in codes)
                PickerItem(label: map[code]!, code: '$code'),
            ],
            onSelected: (item) {
              ref
                  .read(reviewControllerProvider.notifier)
                  .update(
                    (d) => d.copyWith(
                      classCode: int.parse(item.code!),
                      className: item.label,
                      // 사용자가 직접 고른 값이다. 카드가 채웠다는 표시를
                      // 지워야 나중에 카드번호를 고쳐도 이 선택이 안 날아간다.
                      classReason: null,
                      cardNotice: null,
                      classSuggestions: const <ClassChoice>[],
                    ),
                  );
              Navigator.pop(context);
            },
          );
        },
      ),
    );
  }
}

class _EvidencePreview extends StatelessWidget {
  const _EvidencePreview(this.path);

  final String path;

  bool get _isPdf => path.toLowerCase().endsWith('.pdf');

  @override
  Widget build(BuildContext context) {
    // PDF 는 Image.file 로 못 그린다. 파일이 있다는 것만 알려준다.
    if (_isPdf) {
      return AppCard(
        children: [
          Padding(
            padding: const EdgeInsets.all(Gap.lg),
            child: Row(
              children: [
                const Icon(Icons.picture_as_pdf_outlined, size: 28),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Text(
                    'PDF 증빙 · 미리보기 없음',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final file = File(path);
    if (!file.existsSync()) {
      return const NoticeBanner(child: Text('증빙 원본을 찾을 수 없습니다.'));
    }

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => _FullScreenEvidence(file)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.card),
        child: Stack(
          alignment: Alignment.bottomRight,
          children: [
            // 세로로 긴 영수증이 화면을 다 먹지 않게 높이를 묶는다.
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SizedBox(
                width: double.infinity,
                child: Image.file(file, fit: BoxFit.cover),
              ),
            ),
            Container(
              margin: const EdgeInsets.all(Gap.sm),
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.sm,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.zoom_in, size: 14, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    '크게 보기',
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 전체 화면 증빙. 확대해서 글씨를 확인할 수 있어야 한다 —
/// OCR 이 읽은 금액이 맞는지 보려면 결국 원본을 키워봐야 한다.
class _FullScreenEvidence extends StatelessWidget {
  const _FullScreenEvidence(this.file);

  final File file;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('증빙 원본'),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 6,
          child: Image.file(file),
        ),
      ),
    );
  }
}

/// 아직 비어 있는 항목을 앱바 바로 밑에 붙여두는 바.
///
/// ## 왜 스크롤 밖에 두나
///
/// 검토 폼이 길다(증빙·기본·분류·금액·파일명). 비어 있는 항목이 스크롤 안에
/// 있으면 내려가면서 사라진다. 제출 버튼은 위에 고정돼 있는데 왜 눌러도
/// 안 보내지는지 모른 채 위쪽만 들여다보게 된다.
///
/// `pinned` 슬리버로도 항상 띄울 수 있지만, 그건 **스크롤하는 동안 매 프레임
/// 레이아웃 계산에 참여한다.** 스크롤과 무관한 것을 스크롤에 묶을 이유가 없다.
/// 밖에 두면 한 번 배치되고 끝이다.
///
/// 다 채우면 이 위젯 자체가 사라진다 — 폼이 그만큼 넓어진다.
class _MissingFieldsBar extends StatelessWidget {
  const _MissingFieldsBar(this.fields);

  final List<String> fields;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
      decoration: const BoxDecoration(
        color: AppColors.noticeBg,
        // 앱바에 붙은 것처럼 보이게 아래쪽만 선을 둔다.
        border: Border(bottom: BorderSide(color: AppColors.noticeBorder)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 17, color: AppColors.noticeFg),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(
              '아직 비어 있는 항목: ${fields.join(', ')}',
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: AppColors.noticeFg),
            ),
          ),
        ],
      ),
    );
  }
}
