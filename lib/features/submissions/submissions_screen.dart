import 'package:bodit_app/core/theme/tokens.dart';
import 'package:bodit_app/core/widgets/app_widgets.dart';
import 'package:bodit_app/data/local/queue_db.dart';
import 'package:bodit_app/data/providers.dart';
import 'package:bodit_app/features/submissions/submission_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 시안 ⑫ — 내 제출 목록. **부분 실패가 여기서 보인다.**
///
/// 목적지가 3곳이라 Slack 만 실패하는 경우가 생긴다. 어디까지 갔는지를
/// 목적지별로 그대로 보여준다 — 조용히 실패하면 안 된다.
///
/// ## 왜 월로 묶고 검색을 붙였나
///
/// 한 달에 수십 건이 쌓이면 평평한 목록에서 특정 건을 못 찾는다. 회계가
/// 일하는 단위가 **해당년월**이라(Drive 폴더도 시트 필터도 그 기준이다)
/// 같은 단위로 묶는 게 머릿속 모양과 맞는다.
class SubmissionsScreen extends ConsumerStatefulWidget {
  const SubmissionsScreen({super.key});

  @override
  ConsumerState<SubmissionsScreen> createState() => _SubmissionsScreenState();
}

class _SubmissionsScreenState extends ConsumerState<SubmissionsScreen> {
  final _scroll = ScrollController();
  String _query = '';

  /// 이 개수를 넘으면 위아래 이동 버튼을 띄운다. 몇 건뿐인데 버튼이 떠 있으면
  /// 목록을 가리기만 한다.
  static const _jumpButtonsFrom = 8;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _jumpTo(double offset) {
    _scroll.animateTo(
      offset,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(pendingSubmissionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('내 제출'),
        actions: [
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final n = await confirmClearAll(context, ref);
              if (n == null) return;
              messenger.showSnackBar(SnackBar(content: Text('$n건을 지웠습니다.')));
            },
            child: const Text('전체 삭제'),
          ),
        ],
      ),
      body: rows.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: screenPadding,
            child: ErrorDisclosure('목록을 불러오지 못했습니다.', detail: '$e'),
          ),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('아직 제출한 건이 없습니다.'));
          }

          // 파일명에 날짜·업체명·내역·증빙자료명·금액이 전부 들어 있다.
          // 따로 색인을 만들 이유가 없다 — 파일명 하나로 다 걸린다.
          final q = _query.trim().toLowerCase();
          final shown = q.isEmpty
              ? list
              : list
                    .where((s) => s.filename.toLowerCase().contains(q))
                    .toList();

          final groups = _groupByMonth(shown);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, 0),
                child: SearchField(
                  hintText: '업체명·내역·금액으로 검색',
                  // 목록을 보러 들어온 화면이다. 열자마자 키보드가 올라오면
                  // 정작 보려던 목록이 가려진다.
                  autofocus: false,
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: shown.isEmpty
                    ? const Center(child: Text('검색 결과가 없습니다.'))
                    // 이동 버튼을 **목록 위**에 올린다. Scaffold 의
                    // floatingActionButton 으로는 상단 중앙에 둘 수 없고,
                    // 화면 전체를 덮는 Stack 으로 올리면 검색창을 가린다.
                    : Stack(
                        children: [
                          CustomScrollView(
                            controller: _scroll,
                            slivers: [
                              for (final g in groups) ...[
                                // 묶음 헤더를 스크롤 중에도 붙여둔다.
                                SliverPersistentHeader(
                                  pinned: true,
                                  delegate: _MonthHeaderDelegate(
                                    '${g.label} · ${g.rows.length}건',
                                  ),
                                ),
                                SliverPadding(
                                  padding: const EdgeInsets.fromLTRB(
                                    Gap.lg,
                                    0,
                                    Gap.lg,
                                    Gap.lg,
                                  ),
                                  sliver: SliverToBoxAdapter(
                                    child: AppCard(
                                      children: [
                                        for (final s in g.rows)
                                          // 묶음이 연·월을 말하므로 일자만.
                                          SubmissionRow(s, dayOnly: true),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                              const SliverPadding(
                                padding: EdgeInsets.fromLTRB(
                                  Gap.lg,
                                  0,
                                  Gap.lg,
                                  Gap.xxl,
                                ),
                                sliver: SliverToBoxAdapter(
                                  child: NoteText(
                                    '목적지가 3곳이라 하나만 실패할 수 있습니다. '
                                    '실패한 곳만 다시 보내므로 시트에 같은 행이 두 번 들어가지 않습니다.\n'
                                    '행을 왼쪽으로 밀면 목록에서 지울 수 있습니다 — '
                                    '이미 올라간 파일과 시트 행은 지워지지 않습니다.',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (list.length >= _jumpButtonsFrom) ...[
                            Positioned(
                              top: Gap.sm,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: FloatingActionButton.small(
                                  heroTag: 'top',
                                  tooltip: '맨 위로',
                                  onPressed: () => _jumpTo(0),
                                  child: const Icon(Icons.keyboard_arrow_up),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: Gap.sm,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: FloatingActionButton.small(
                                  heroTag: 'bottom',
                                  tooltip: '맨 아래로',
                                  onPressed: () =>
                                      _jumpTo(_scroll.position.maxScrollExtent),
                                  child: const Icon(Icons.keyboard_arrow_down),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 월 헤더를 **스크롤 중에도 붙여둔다.**
///
/// 월로 묶은 이유가 회계가 일하는 단위가 해당년월이기 때문인데, 스크롤하는
/// 동안 지금 보는 게 몇 월 건인지 모르면 묶은 의미가 없다.
///
/// pinned 헤더가 여럿이면 다음 달 헤더가 앞 것을 밀어낸다 — 그래서 **그 달의
/// 행이 보이는 동안만** 그 달 헤더가 남는다. 따로 계산할 게 없다.
class _MonthHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _MonthHeaderDelegate(this.label);

  final String label;

  /// `SectionHeader` 의 높이(Gap.lg + labelMedium 16px + Gap.sm).
  ///
  /// Sliver 는 높이를 **미리** 알아야 해서 재지 못하고 적어둔다. 타이포
  /// 스케일을 건드리면 여기도 같이 봐야 한다 — 작으면 글자가 잘린다.
  static const _height = 48.0;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // 배경을 깔지 않으면 카드가 헤더 뒤로 지나가며 글자가 겹쳐 보인다.
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
        child: Align(
          alignment: Alignment.centerLeft,
          child: SectionHeader(label),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_MonthHeaderDelegate old) => old.label != label;
}

/// 한 달치 묶음.
class _MonthGroup {
  const _MonthGroup(this.label, this.rows);
  final String label;
  final List<Submission> rows;
}

/// **소속날짜** 기준으로 월별로 묶는다.
///
/// 제출한 날이 아니라 소속날짜인 이유: 9월에 올린 8월 영수증은 회계에게
/// 8월 건이다. Drive 폴더도 시트 필터도 그 기준이라 여기만 다르면 헷갈린다.
///
/// 소속날짜를 못 읽으면 제출한 날로 떨어진다 — 묶음에서 빠지는 것보다 낫다.
List<_MonthGroup> _groupByMonth(List<Submission> rows) {
  final buckets = <String, List<Submission>>{};
  for (final r in rows) {
    final d = belongDateOf(r) ?? r.createdAt;
    final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
    (buckets[key] ??= <Submission>[]).add(r);
  }
  // 최근 달이 위로. 지금 처리하는 건이 보통 이번 달 것이다.
  final keys = buckets.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final k in keys)
      _MonthGroup(
        '${k.split('-')[0]}년 ${int.parse(k.split('-')[1])}월',
        buckets[k]!,
      ),
  ];
}
