import 'dart:async';

import 'package:bodit_app/core/theme/tokens.dart';
import 'package:bodit_app/core/utils/filename.dart';
import 'package:bodit_app/core/widgets/app_widgets.dart';
import 'package:bodit_app/data/providers.dart';
import 'package:bodit_app/features/review/review_controller.dart';
import 'package:bodit_app/models/entry_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 시안 ④⑤⑥⑦⑧⑨ — 검토 폼.
///
/// 확신 낮은 필드를 표시하지 않는다(ADR Decision 11). 어차피 전부 훑어야 하는데
/// 특정 필드만 찍으면 나머지를 안 보게 된다. 대신 **비어 있는 칸**은 알려준다 —
/// 그건 확신의 문제가 아니라 제출이 막히는 문제다.
class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          TextButton(
            onPressed: state.allComplete ? () => _submit(context, ref) : null,
            child: Text(state.isMulti ? '전체 제출' : '제출'),
          ),
        ],
      ),
      body: ListView(
        padding: screenPadding,
        children: [
          // 시안 ⑥ — 여러 건일 때 건별 목록
          if (state.isMulti) ...[
            SectionHeader('읽은 증빙 ${state.drafts.length}건'),
            AppCard(
              children: [
                for (var i = 0; i < state.drafts.length; i++)
                  _DraftRow(
                    draft: state.drafts[i],
                    selected: i == state.selected,
                    onTap: () =>
                        ref.read(reviewControllerProvider.notifier).select(i),
                  ),
              ],
            ),
            const NoteText('한 건씩 눌러서 확인합니다. 전부 채우면 한 번에 제출됩니다.'),
          ],

          const SectionHeader('기본'),
          AppCard(
            children: [
              LabeledRow(
                label: '소속날짜',
                value: _fmtDate(draft.belongDate),
                placeholder: '입력 필요',
                onTap: () => _pickDate(context, ref, draft),
              ),
              LabeledRow(
                label: '지출날짜',
                value: _fmtDate(draft.spendDate ?? draft.belongDate),
                placeholder: '소속날짜와 동일',
                onTap: () {},
              ),
              LabeledRow(
                label: '업체명',
                value: draft.vendor,
                placeholder: '입력 필요',
                onTap: () => _editText(
                  context, ref, '업체명', draft.vendor,
                  (d, v) => d.copyWith(vendor: v),
                ),
              ),
              LabeledRow(
                label: '내역',
                value: draft.description,
                placeholder: '입력 필요',
                onTap: () => _editText(
                  context, ref, '내역', draft.description,
                  (d, v) => d.copyWith(description: v),
                ),
              ),
            ],
          ),

          // 시안 ⑦ — 영수증에 없는 항목은 과거 이력으로 추천
          const SectionHeader('분류 — 영수증에 없는 항목'),
          AppCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(Gap.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('비목', style: Theme.of(context).textTheme.bodySmall),
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
                          draft.expenseCategory == null ? '선택하기' : '바꾸기',
                          onTap: () => _pickCategory(context, ref),
                        ),
                      ],
                    ),
                    // 근거 없이 채워두면 사용자가 못 믿고 전부 다시 확인한다.
                    if (draft.suggestionReason != null)
                      SuggestReason(draft.suggestionReason!),
                  ],
                ),
              ),
            ],
          ),

          const SectionHeader('금액'),
          AppCard(
            children: [
              LabeledRow(
                label: '총금액',
                value: _fmtAmount(draft.totalAmount),
                placeholder: '입력 필요',
                onTap: () => _editAmount(
                  context, ref, '총금액', draft.totalAmount,
                  (d, v) => d.copyWith(totalAmount: v),
                ),
              ),
              LabeledRow(
                label: '공급가액',
                value: _fmtAmount(draft.supplyAmount),
                placeholder: '총금액과 동일',
              ),
              LabeledRow(
                label: '부가세',
                value: _fmtAmount(draft.vatAmount ?? 0),
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
                  OutlinedButton(
                    onPressed: () =>
                        ref.read(reviewControllerProvider.notifier).applyVatSplit(),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: Gap.md),
                    ),
                    child: const Text('1.1로 나누기'),
                  ),
                ],
              ),
            ),
          ],

          const SectionHeader('저장될 파일명'),
          AppCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(Gap.lg),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        draft.filename,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _editFilename(context, ref, draft),
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
          if (draft.missingFields.isNotEmpty) ...[
            const SizedBox(height: Gap.lg),
            NoticeBanner(
              child: Text('아직 비어 있는 항목: ${draft.missingFields.join(', ')}'),
            ),
          ],
          const SizedBox(height: Gap.xl),
        ],
      ),
    );
  }

  Future<void> _submit(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final n = await ref.read(reviewControllerProvider.notifier).enqueueAll();
      // 큐에 넣기만 한다 — 전송은 홈에서 [전송 시도] 를 눌러야 나간다.
      messenger.showSnackBar(
        SnackBar(content: Text('$n건을 저장했습니다. 홈에서 전송 시도를 눌러주세요.')),
      );
      navigator.pop();
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _pickCategory(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _CategoryPickerSheet(),
    );
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
    final v = await _prompt(context, label, initial ?? '');
    if (v == null) return;
    ref.read(reviewControllerProvider.notifier).update((d) => apply(d, v));
  }

  Future<void> _editAmount(
    BuildContext context,
    WidgetRef ref,
    String label,
    int? initial,
    EntryDraft Function(EntryDraft, int) apply,
  ) async {
    final v = await _prompt(context, label, initial?.toString() ?? '',
        keyboard: TextInputType.number);
    final n = int.tryParse((v ?? '').replaceAll(RegExp('[^0-9-]'), ''));
    if (n == null) return;
    ref.read(reviewControllerProvider.notifier).update((d) => apply(d, n));
  }

  Future<void> _editFilename(
    BuildContext context,
    WidgetRef ref,
    EntryDraft draft,
  ) async {
    final v = await _prompt(context, '파일명 수정', draft.filename, maxLines: 2);
    if (v == null) return;
    // 사용자가 직접 친 값에도 치환 규칙을 적용한다 — `/` 하나로 Drive 동기화가 깨진다.
    ref
        .read(reviewControllerProvider.notifier)
        .update((d) => d.copyWith(filenameOverride: sanitizeSegment(v)));
  }

  static Future<String?> _prompt(
    BuildContext context,
    String title,
    String initial, {
    TextInputType? keyboard,
    int maxLines = 1,
  }) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: keyboard,
          maxLines: maxLines,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  static String? _fmtDate(DateTime? d) => d == null
      ? null
      : '${d.year}-${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';

  static String? _fmtAmount(int? v) => v?.toString().replaceAllMapped(
            RegExp(r'(\d)(?=(\d{3})+$)'),
            (m) => '${m[1]},',
          );
}

/// 시안 ④ — OCR 진행 중.
class _ReadingView extends StatelessWidget {
  const _ReadingView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('분석 중')),
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: Gap.lg),
            Text('영수증을 읽는 중…'),
            SizedBox(height: Gap.sm),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: Gap.xxl),
              child: Text(
                '비목과 분류코드는 영수증에 없습니다.\n'
                '과거에 같은 업체를 어떻게 처리했는지 보고 제안합니다.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.neutralFg),
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
class _CategoryPickerSheet extends ConsumerWidget {
  const _CategoryPickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(expenseCategoriesProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (_, controller) => categories.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: screenPadding,
            child: ErrorDisclosure('비목을 불러오지 못했습니다.', detail: '$e'),
          ),
        ),
        // 빈 목록은 provider 가 이미 걸러서 던진다(탭이 비었다고 알려준다).
        // 여기 오는 list 는 항상 하나 이상이다.
        data: (list) {
          return ListView.builder(
            controller: controller,
            itemCount: list.length + 1,
            itemBuilder: (_, i) {
              if (i == 0) {
                return const Padding(
                  padding: EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.sm),
                  child: Text(
                    '비목 선택',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                );
              }
              final name = list[i - 1];
              return ListTile(
                title: Text(name),
                onTap: () {
                  ref
                      .read(reviewControllerProvider.notifier)
                      .update((d) => d.copyWith(expenseCategory: name));
                  Navigator.pop(context);
                },
              );
            },
          );
        },
      ),
    );
  }
}
