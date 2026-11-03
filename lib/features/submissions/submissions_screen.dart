import 'dart:async';
import 'dart:math' as math;

import 'package:bodit_app/core/theme/tokens.dart';
import 'package:bodit_app/core/widgets/app_widgets.dart';
import 'package:bodit_app/data/local/queue_db.dart';
import 'package:bodit_app/data/providers.dart';
import 'package:bodit_app/features/submissions/sending_banner.dart';
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
  const SubmissionsScreen({super.key, this.focusId});

  /// 열면서 **그 건으로 스크롤할** 큐 행 id (`/submissions?focus=12`).
  ///
  /// 전송 진행 띠를 누르면 여기로 온다 — 맨 위로 떨어뜨리면 수십 건 중
  /// 어느 것이 방금 제출한 그건지 다시 찾아야 한다.
  final int? focusId;

  @override
  ConsumerState<SubmissionsScreen> createState() => _SubmissionsScreenState();
}

class _SubmissionsScreenState extends ConsumerState<SubmissionsScreen> {
  final _scroll = ScrollController();
  String _query = '';

  /// 지금 가리키고 있는 건. 그 행에만 [_focusKey] 와 강조색이 붙는다.
  int? _focus;

  /// 가리킨 행의 위치를 알아내는 열쇠. **한 번에 한 행에만** 붙는다.
  final GlobalKey _focusKey = GlobalKey();

  /// 강조를 거두는 타이머. 계속 칠해두면 "이 건이 특별하다" 로 읽힌다.
  Timer? _unfocus;

  /// 이 개수를 넘으면 위아래 이동 버튼을 띄운다. 몇 건뿐인데 버튼이 떠 있으면
  /// 목록을 가리기만 한다.
  static const _jumpButtonsFrom = 8;

  @override
  void initState() {
    super.initState();
    final id = widget.focusId;
    if (id == null) return;
    // 첫 build 전이라 setState 를 부르지 않는다 — 어차피 바로 그려진다.
    // 스크롤은 그려진 **다음**이라야 하므로 [_scrollToFocus] 가 프레임을 기다린다.
    _focus = id;
    unawaited(_scrollToFocus());
  }

  @override
  void dispose() {
    _unfocus?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  /// 그 건으로 가리키는 것을 **화면을 보는 중에** 바꾼다 —
  /// 이미 목록에 있는 사용자가 진행 띠를 눌렀을 때.
  Future<void> _focusOn(int id) async {
    setState(() => _focus = id);
    await _scrollToFocus();
  }

  /// [_focus] 가 가리키는 행이 보이도록 스크롤하고 잠깐 강조한다.
  ///
  /// ## 왜 한 번에 못 가나
  ///
  /// 목록은 lazy 다 — **화면 밖의 행은 아직 만들어지지도 않았다.** 그래서
  /// `GlobalKey` 가 가리킬 엘리먼트가 없고, `ensureVisible` 도 쓸 수 없다.
  /// 행 높이가 제각각(칩·실패 사유 줄이 붙는다)이라 위치를 계산할 수도 없다.
  ///
  /// 그래서 **한 화면씩 내려가며** 키가 잡히는지 보고, 잡히면 그 자리에
  /// 맞춘다. 보통 찾는 건은 최근 제출이라 첫 화면에서 바로 끝난다.
  ///
  /// 걸음 수를 제한한다 — 검색에 걸러졌거나 방금 지운 건이면 아무리 내려도
  /// 안 나온다. 그때는 멈추고 **왜 못 찾았는지 말한다**(조용히 끝내지 않는다).
  Future<void> _scrollToFocus() async {
    _unfocus?.cancel();

    var found = false;
    for (var step = 0; step < 24; step++) {
      if (!mounted) return;
      final ctx = _focusKey.currentContext;
      if (ctx != null && ctx.mounted) {
        found = true;
        await Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          // 맨 위에 딱 붙이면 떠 있는 [맨 위로] 버튼과 월 헤더에 가린다.
          alignment: 0.3,
        );
        break;
      }
      // 목록이 아직 안 그려졌다(스트림 로딩 중). 다음 프레임에 다시 본다.
      if (!_scroll.hasClients) {
        await WidgetsBinding.instance.endOfFrame;
        continue;
      }
      final pos = _scroll.position;
      // 끝까지 내려왔는데 없다 — 더 내려갈 곳이 없으니 그만둔다.
      if (pos.pixels >= pos.maxScrollExtent) break;
      await _scroll.animateTo(
        math.min(pos.pixels + pos.viewportDimension * 0.8, pos.maxScrollExtent),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    }

    if (!mounted) return;
    if (!found) {
      // 거의 이 경우다 — 검색어가 걸려 그 행이 목록에 없다.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _query.trim().isEmpty
                ? '그 건을 목록에서 찾지 못했습니다.'
                : '검색 결과에 없어서 찾지 못했습니다. 검색을 비우고 다시 눌러주세요.',
          ),
        ),
      );
    }
    _unfocus = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _focus = null);
    });
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
      // 전송 진행 띠는 **스크롤 밖 맨 위**에 둔다 — 목록 안에 두면 밀려
      // 사라진다. 여기서 누르면 화면을 또 띄우지 않고 그 자리에서 스크롤한다.
      body: Column(
        children: [
          SendingBanner(onTap: (id) => unawaited(_focusOn(id))),
          Expanded(child: _list(rows)),
        ],
      ),
    );
  }

  Widget _list(AsyncValue<List<Submission>> rows) {
    return rows.when(
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
            : list.where((s) => s.filename.toLowerCase().contains(q)).toList();

        final groups = _groupByMonth(shown);

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, 0),
              child: SearchField(
                hintText: '업체명·내역·금액으로 검색',
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
                                      // 구분선은 카드가 아니라 **여기서** 넣는다
                                      // (`RowDivider` 참조).
                                      for (final (i, s) in g.rows.indexed) ...[
                                        if (i > 0) const RowDivider(),
                                        _row(s),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ],
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
    );
  }

  /// 목록의 한 행. **가리킨 건이면** 열쇠와 강조색을 얹는다.
  ///
  /// 스크롤만 해두면 화면에 들어온 여러 행 가운데 어느 줄이 그건인지 알 수
  /// 없다 — 날짜·업체명이 비슷한 행이 줄줄이 있다. 잠깐 칠해서 가리킨다.
  Widget _row(Submission s) {
    // 묶음 헤더가 연·월을 말하므로 행에서는 일자만.
    final row = SubmissionRow(s, dayOnly: true);
    if (s.id != _focus) return row;
    return KeyedSubtree(
      key: _focusKey,
      child: ColoredBox(color: AppColors.suggestBg, child: row),
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
