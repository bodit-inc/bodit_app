/// 긴 목록에서 하나 고르는 바텀시트.
///
/// ## 왜 하나로 합쳤나
///
/// 비목(33개)과 분류(46개)를 고르는 화면이 따로 있었는데 생김새가 달랐다 —
/// 분류에만 검색이 있고, 비목은 정렬도 안 돼 있어서 스크롤로 찾아야 했다.
/// 같은 일을 하는 화면이 둘로 갈라지면 한쪽만 고치게 된다.
///
/// 그래서 **보이는 부분을 여기로 끌어올렸다.** 목록을 어디서 읽어오는지는
/// 화면이 알고(비목·분류 모두 시트에서 읽는다), 여기는 받은 목록을 보여주고
/// 검색하고 하나를 돌려주는 일만 한다 — `core` 는 기능을 모르는 층이다.
library;

import 'package:bodit_app/core/theme/tokens.dart';
import 'package:bodit_app/core/widgets/fields.dart';
import 'package:flutter/material.dart';

/// 고를 수 있는 항목 하나.
@immutable
class PickerItem {
  const PickerItem({required this.label, this.code});

  /// 화면에 보이고 검색에 걸리는 이름.
  final String label;

  /// 왼쪽에 고정폭으로 붙는 코드. 분류처럼 **번호로 말하는** 목록에만 있다.
  /// 비목은 번호가 없으므로 null 이다.
  final String? code;

  /// 코드로도 이름으로도 찾을 수 있다 — 회계 담당자는 "23번" 이라고 말하고
  /// 제출자는 "CTS" 라고 말한다.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return label.toLowerCase().contains(q) || (code ?? '').contains(q);
  }
}

class PickerSheet extends StatefulWidget {
  const PickerSheet({
    required this.searchHint,
    required this.items,
    required this.onSelected,
    this.title,
    this.header,
    this.selectedLabel,
    super.key,
  });

  /// 목록 위에 붙는 제목. **화면으로 쓸 때는 비운다** — 앱바가 이미 같은
  /// 말을 하고 있으면 같은 글자가 두 줄 연달아 뜬다.
  final String? title;

  /// 검색창 **위**에 들어가는 자리. 추천 칩처럼 "검색하기 전에 먼저 보는 것"
  /// 을 여기 둔다.
  ///
  /// 목록 쪽(아래)이 아니라 위인 이유: 칩은 **검색을 건너뛰게 하려고** 띄운다.
  /// 검색창 아래에 두면 사용자가 먼저 검색어를 치고, 그러면 칩이 할 일이 없다.
  final Widget? header;

  final String searchHint;
  final List<PickerItem> items;

  /// 지금 고른 값. **그 줄 전체를 물들인다** — 목록이 길어서 뭘 고른
  /// 상태인지 안 보이면 같은 걸 또 누른다.
  final String? selectedLabel;

  final void Function(PickerItem) onSelected;

  @override
  State<PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<PickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final shown = widget.items.where((i) => i.matches(_query)).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.title != null) ...[
                Text(
                  widget.title!,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: Gap.sm),
              ],
              if (widget.header != null) ...[
                widget.header!,
                const SizedBox(height: Gap.md),
              ],
              SearchField(
                hintText: widget.searchHint,
                onChanged: (v) => setState(() => _query = v),
              ),
            ],
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? const Center(child: Text('검색 결과가 없습니다.'))
              : ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (_, i) {
                    final item = shown[i];
                    final isSelected = item.label == widget.selectedLabel;
                    // 고른 줄은 **줄 전체의 색**으로 말한다.
                    //
                    // 예전엔 오른쪽 끝에 체크를 찍었다. 34개가 세로로 긴
                    // 목록에서 그 작은 표시는 **글자와 반대쪽 끝**에 있어서,
                    // 이름을 읽는 눈과 표시를 찾는 눈이 따로 움직인다 —
                    // 뭘 골랐는지 확인하려고 목록을 다시 훑게 된다.
                    // 줄이 물들면 스크롤 중에도 그 자리가 먼저 보인다.
                    //
                    // 색은 추천 칩이 고른 상태일 때와 같다(`SuggestChip`) —
                    // 같은 화면에서 "이게 지금 값이다" 를 두 가지 색으로
                    // 말하면 둘이 다른 뜻인 줄 읽힌다.
                    final labelStyle = Theme.of(context).textTheme.labelMedium
                        ?.copyWith(
                          color: isSelected ? AppColors.suggestFg : null,
                          fontWeight: isSelected ? FontWeight.w600 : null,
                        );
                    return ListTile(
                      dense: true,
                      tileColor: isSelected ? AppColors.suggestBg : null,
                      leading: item.code == null
                          ? null
                          : SizedBox(
                              width: 34,
                              child: Text(
                                item.code!,
                                textAlign: TextAlign.end,
                                style: labelStyle?.copyWith(
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                      // 왼쪽 코드 칸과 **같은 슬롯**으로 맞춘다. ListTile 의
                      // 기본 제목은 bodyLarge(18px)인데 코드는 labelMedium(16px)
                      // 이라, 한 줄에 나란히 있는 두 글자 크기가 달랐다.
                      title: Text(item.label, style: labelStyle),
                      onTap: () => widget.onSelected(item),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// 한글 이름을 ㄱ·ㄴ·ㄷ 순으로.
///
/// 완성형 한글은 코드포인트 순서가 곧 가나다 순서라 `compareTo` 로 충분하다.
/// 영문·숫자로 시작하는 이름(`IP` 등)은 한글보다 앞에 모인다 — 섞어 흩뿌리는
/// 것보다 한 덩어리로 모이는 쪽이 찾기 쉽다.
int compareKorean(String a, String b) => a.compareTo(b);
