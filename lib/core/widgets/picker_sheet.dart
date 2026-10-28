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
    required this.title,
    required this.searchHint,
    required this.items,
    required this.onSelected,
    this.selectedLabel,
    super.key,
  });

  final String title;
  final String searchHint;
  final List<PickerItem> items;

  /// 지금 고른 값. 체크를 찍어준다 — 목록이 길어서 뭘 고른 상태인지
  /// 안 보이면 같은 걸 또 누른다.
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
              Text(widget.title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: Gap.sm),
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
                    return ListTile(
                      dense: true,
                      leading: item.code == null
                          ? null
                          : SizedBox(
                              width: 34,
                              child: Text(
                                item.code!,
                                textAlign: TextAlign.end,
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(fontFamily: 'monospace'),
                              ),
                            ),
                      title: Text(item.label),
                      trailing: isSelected
                          ? const Icon(Icons.check, size: 18)
                          : null,
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
