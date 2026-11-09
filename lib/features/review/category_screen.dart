/// OCR 로딩과 검토 폼 **사이**에 서는 비목 화면.
///
/// ## 왜 화면을 하나 더 두는가
///
/// 비목은 영수증에 안 적혀 있어서 OCR 이 못 뽑는다. 업체 이력으로 채워지면
/// 그걸로 끝이지만(그때는 이 화면이 서지 않는다), 못 채운 건은 사용자가 34개
/// 중에서 골라야 한다. 그런데 폼 안에서는 그 칸이 다른 열네 칸과 **같은
/// 무게**로 보이고, 비목은 필수가 아니라(`EntryDraft.isComplete`) 비어도
/// 제출이 막히지 않는다 — 그래서 빈 채로 올라간 행이 쌓였고, 회계 담당자는
/// 그 행마다 제출자에게 되물었다.
///
/// 폼 **앞**에 세우면 비목 하나만 보고 한 번 판단한다. 그러고 폼으로 넘어가면
/// 그 칸은 이미 채워져 있다.
///
/// ## 라우트가 아니다
///
/// `ReviewScreen` 이 상태를 보고 이 화면을 대신 그린다
/// (`ReviewState.categoryQueue`) — OCR 진행 화면(`_ReadingView`)과 같은
/// 방식이다. 라우트로 나누면 뒤로가기로 이 화면을 건너뛸 수 있는데, 그러면
/// 폼의 값은 어디에도 저장돼 있지 않으므로 OCR 결과를 통째로 잃는다.
///
/// ## 고른 값은 [다음] 을 눌러야 적힌다
///
/// 칩이나 목록을 누르는 것은 **고르는 것**이고 넘어가는 것은 버튼이다.
/// 누르자마자 넘어가면 잘못 누른 사용자가 되돌릴 자리가 없다 — 폼까지 가서
/// 다시 고쳐야 한다. 그래서 선택은 이 화면의 지역 상태로 들고 있다가
/// 버튼에서 한 번에 넘긴다.
library;

import 'package:bodit_app/core/theme/tokens.dart';
import 'package:bodit_app/core/widgets/app_widgets.dart';
import 'package:bodit_app/data/providers.dart';
import 'package:bodit_app/features/review/review_controller.dart';
import 'package:bodit_app/models/entry_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CategoryScreen extends ConsumerStatefulWidget {
  const CategoryScreen({required this.index, super.key});

  /// 지금 묻고 있는 건. `ReviewState.categoryQueue` 의 맨 앞이다.
  ///
  /// `selected`(폼에서 보고 있는 건)와 다르다 — 이 화면은 폼이 열리기 전에
  /// 서므로 사용자가 고른 건이라는 개념이 없고, 빈 건을 앞에서부터 묻는다.
  final int index;

  @override
  ConsumerState<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends ConsumerState<CategoryScreen> {
  /// 지금 고른 비목. null 이면 아무것도 안 골랐다 — 버튼이 `비목없이 다음` 이 된다.
  String? _picked;

  /// 같은 것을 다시 누르면 **선택이 풀린다.**
  ///
  /// 잘못 누른 뒤 비목 없이 넘어갈 길이 있어야 한다. 선택을 못 풀면
  /// 사용자는 아무 비목이나 고른 채로 넘어가고, 그건 틀린 비목인데
  /// 시트는 append-only 라 되돌릴 수 없다.
  void _toggle(String category) {
    setState(() => _picked = _picked == category ? null : category);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reviewControllerProvider);
    final draft = widget.index < state.drafts.length
        ? state.drafts[widget.index]
        : null;

    // 대기열과 목록이 어긋난 경우. 일어나면 안 되지만 빈 화면으로 두지 않는다.
    if (draft == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('비목')),
        body: const Center(child: Text('증빙이 없습니다.')),
      );
    }

    final categories = ref.watch(expenseCategoriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('비목')),
      body: categories.when(
        loading: () => Column(
          children: [
            Padding(
              padding: screenPadding,
              child: _header(context, state, draft),
            ),
            const Expanded(child: Center(child: CircularProgressIndicator())),
          ],
        ),
        // 목록을 못 읽어도 **화면을 막지 않는다.** 추천 칩은 과거 행에서 온
        // 것이라 마스터와 무관하게 쓸 수 있고, 하단 버튼으로 비목 없이
        // 넘어갈 수도 있어야 한다 — 여기서 막으면 시트 설정 문제 하나로
        // 증빙 제출이 통째로 멈춘다.
        error: (e, _) => ListView(
          padding: screenPadding,
          children: [
            _header(context, state, draft),
            const SizedBox(height: Gap.xl),
            ErrorDisclosure('비목 목록을 불러오지 못했습니다.', detail: '$e'),
            const SizedBox(height: Gap.lg),
            Center(
              child: RetryButton(
                onPressed: () => ref.invalidate(expenseCategoriesProvider),
              ),
            ),
          ],
        ),
        data: (list) {
          // 시트에 적힌 순서는 사람이 추가한 순서라 규칙이 없다.
          // 34개를 눈으로 훑어야 하므로 가나다로 세운다 — 비목 바텀시트와
          // 같은 규칙이다.
          final sorted = [...list]..sort(compareKorean);
          return PickerSheet(
            // 앱바가 이미 `비목` 이라고 적혀 있다. 제목을 또 두면 같은 말이
            // 두 줄 연달아 뜬다.
            header: _header(context, state, draft, master: list),
            searchHint: '이름으로 검색 (예: 도서, 여비)',
            selectedLabel: _picked,
            items: [for (final name in sorted) PickerItem(label: name)],
            // **고르고 끝이 아니다** — 닫지 않고 체크만 옮긴다.
            // 넘어가는 것은 하단 버튼이다(위 library 주석).
            onSelected: (item) => _toggle(item.label),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        minimum: screenPadding,
        child: FilledButton(
          onPressed: () =>
              ref.read(reviewControllerProvider.notifier).answerCategory(_picked),
          // 글자가 **무엇이 일어날지** 말한다. 안 골랐을 때도 `다음` 이면
          // 사용자는 고른 줄 알고 넘어가고, 빈 비목으로 제출된다.
          child: Text(_picked == null ? '비목없이 다음' : '다음'),
        ),
      ),
    );
  }

  /// 검색창 위에 서는 부분 — **어느 증빙인지**와 **짐작한 비목 칩**.
  ///
  /// 칩 줄이 둘이다. 출처가 다르고 **세기가 다르기 때문**이다:
  ///
  ///   1. 과거에 비슷한 건을 어떻게 처리했는지 센 것(`CategoryGuess`) —
  ///      건수가 붙는다. 기록이라 더 세다
  ///   2. 품목을 읽고 짐작한 것(`CategoryAdvisor`) — 셀 것이 없다.
  ///      과거에 안 산 물건은 이 줄만 뜬다
  ///
  /// 한 줄로 합치지 않는다. 섞으면 `도서인쇄비 3건` 과 `장비구입비` 가 나란히
  /// 서서, 뒤쪽도 어디서 세어온 값인 줄 읽힌다. 근거 문구도 하나로 못 적는다.
  ///
  /// [master] 를 받으면 그 안에 있는 비목만 띄운다. 과거 행에서 읽은 이름은
  /// 마스터에서 빠진 옛 비목일 수 있는데, 그걸 눌러 제출하면 마스터에 없는
  /// 값이 시트에 들어간다(그 칸은 34개 중 하나여야 한다).
  /// 마스터를 **못 읽었을 때는 걸러내지 않는다** — 그때 거르면 고를 것이
  /// 하나도 없고, 과거에 실제로 쓴 비목이라는 사실은 그대로다.
  Widget _header(
    BuildContext context,
    ReviewState state,
    EntryDraft draft, {
    List<String>? master,
  }) {
    bool known(String name) => master == null || master.contains(name);

    final guesses = draft.categoryGuesses
        .where((t) => known(t.category))
        .toList();
    final hints = draft.categoryHints.where(known).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _subject(state, draft),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: AppColors.neutralFg,
          ),
        ),

        // 1. 과거에 비슷한 건이 있었다 — 센 것이라 건수를 같이 적는다.
        if (guesses.isNotEmpty) ...[
          const SizedBox(height: Gap.lg),
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [for (final t in guesses) _chip(t.category, t.label)],
          ),
          if (draft.categoryGuessReason != null)
            _reason(context, draft.categoryGuessReason!),
        ],

        // 2. 품목을 읽고 짐작했다 — 건수가 없다. 그래서 **어디서 온
        //    값인지를 문구가 말한다**("영수증 품목으로 짐작했습니다").
        //    그 말이 없으면 사용자는 이것도 과거 기록인 줄 안다.
        if (hints.isNotEmpty) ...[
          const SizedBox(height: Gap.lg),
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [for (final name in hints) _chip(name, name)],
          ),
          _reason(context, _hintLine(draft)),
        ],
      ],
    );
  }

  /// 칩 하나. [value] 가 고르는 값이고 [label] 은 보이는 글자다 —
  /// 과거 이력 칩은 건수까지 적으므로 둘이 다르다(`도서인쇄비 2건`).
  Widget _chip(String value, String label) => SuggestChip(
    label,
    selected: _picked == value,
    // **고르지 않은 칩을 빨갛게 두지 않는다.** 기본 모양이 danger 색인데,
    // 이건 틀린 값이 아니라 그럴듯한 후보다 — 검토 폼의 "이 업체의 다른
    // 비목" 과 같은 이유다.
    initialState: _picked != value,
    onTap: () => _toggle(value),
  );

  /// 칩 아래 한 줄. 왜 이게 떴는지 모르면 사용자는 맨 위 칩을 누르거나
  /// 전부 무시하는 수밖에 없다.
  Widget _reason(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: Gap.sm),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: AppColors.neutralFg,
      ),
    ),
  );

  /// 모델 짐작의 근거 줄. **출처를 먼저 말한다** — 뒤에 붙는 문장은 모델이
  /// 적어준 이유라 "과거에 그랬다" 처럼 읽힐 수 있다.
  String _hintLine(EntryDraft draft) {
    final reason = draft.categoryHintReason;
    return reason == null
        ? '영수증 품목으로 짐작한 비목입니다.'
        : '영수증 품목으로 짐작했습니다 — $reason';
  }

  /// 지금 묻고 있는 증빙이 무엇인지 한 줄.
  ///
  /// **없으면 안 된다.** 비목은 "무엇을 샀는가" 로 정하는 값인데, 여러 장을
  /// 찍었으면 지금 화면이 어느 장인지 알 수 없다. 금액은 넣지 않는다 —
  /// 비목을 가르는 정보가 아니고, 줄이 길어지면 업체명이 잘린다.
  String _subject(ReviewState state, EntryDraft draft) {
    final parts = <String>[
      if (state.isMulti) '${widget.index + 1}/${state.drafts.length}번째 건',
      if ((draft.vendor ?? '').isNotEmpty) draft.vendor!,
      if ((draft.description ?? '').isNotEmpty) draft.description!,
    ];
    // OCR 이 둘 다 못 읽었다. 빈 줄을 두면 왜 비었는지 모른다.
    return parts.isEmpty ? '업체명·내역을 읽지 못한 증빙입니다.' : parts.join(' · ');
  }
}
