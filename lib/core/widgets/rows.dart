/// 카드 안에 들어가는 줄.
///
/// 시안의 `.row` 가 여기 대응한다. 라벨 + 값 + (선택) 부가설명 + 우측 요소.
library;

import 'package:bodit_app/core/theme/tokens.dart';
import 'package:bodit_app/models/certainty.dart';
import 'package:flutter/material.dart';

/// `라벨 ......... 값` 한 줄. 시안의 `.row`
///
/// [onTap] 을 주면 누를 수 있는 행이 된다(오른쪽에 › 표시).
class LabeledRow extends StatelessWidget {
  const LabeledRow({
    required this.label,
    super.key,
    this.value,
    this.placeholder,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.warnPlaceholder = false,
    this.editable = false,
    this.certainty = Certainty.unknown,
    this.valueWidget,
  });

  final String label;
  final String? value;

  /// 값 아래에 붙는 작은 설명 줄. 전송 진행 상태·실패 사유처럼
  /// **한 줄로 안 끝나는 정보**를 담는다.
  final String? subtitle;

  /// 값이 비었을 때 회색으로 보여줄 안내 문구.
  final String? placeholder;

  /// 안내 문구를 **경고색**으로 띄운다.
  ///
  /// 회색 안내는 "비어 있다" 로만 읽히고 넘어간다. OCR 이 못 채워서
  /// **사람이 직접 써야 하는 칸**은 그것과 구분돼야 한다 — 회계 담당자가
  /// 그 칸이 비어서 되묻는 일이 실제로 있었다.
  final bool warnPlaceholder;

  /// **글자를 고치는 줄**이다 — 어디론가 넘어가는 줄이 아니라.
  ///
  /// 둘 다 `›` 를 달고 있었더니 "눌러서 다음 화면으로 간다" 로만 읽혔다.
  /// 고치는 줄은 연필과 밑줄을 달아 입력칸처럼 보이게 한다. 날짜·비목처럼
  /// 목록에서 고르는 줄은 그대로 `›` 다.
  final bool editable;

  /// OCR 이 그 값을 얼마나 확신했는가.
  ///
  /// 값이 비어 있는 것과는 다른 상태다 — 비면 사용자가 바로 알아채지만,
  /// 잘못 읽은 값은 그럴듯해 보여서 그냥 지나간다. 그래서 값 쪽에 표식을 단다.
  ///
  /// **두 단계를 다르게 그린다.** `0.39` 와 `0.69` 는 할 일이 다르다 —
  /// 앞쪽은 값을 믿을 수 없고 뒤쪽은 한 번 훑으면 된다. 기준은
  /// `EntryDraft.certaintyOf`.
  ///
  /// 드물게 떠야 쓸모가 있다. 절반이 뜨면 아무도 안 본다.
  final Certainty certainty;

  /// 값 자리에 들어갈 위젯. 주면 [value]·[placeholder] 대신 이걸 그린다.
  ///
  /// [InlineEditRow] 가 **입력칸을 그 자리에 끼우는 데** 쓴다. 보기 모드와
  /// 편집 모드가 같은 줄 구조를 써야 탭했을 때 글자가 움직이지 않는다.
  final Widget? valueWidget;

  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final hasValue = (value ?? '').isNotEmpty;

    final row = Row(
      children: [
        SizedBox(
          width: 84,
          child: Text(
            label,
            style: t.bodySmall?.copyWith(color: AppColors.neutralFg),
          ),
        ),
        Expanded(
          child: Container(
            // 입력칸처럼 보이게 하는 밑줄. 값이 오른쪽 정렬이라 밑줄도
            // 글자 폭이 아니라 줄 전체에 깔린다 — 빈 칸도 누를 자리가 보인다.
            decoration: editable
                ? const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFD8D8DE)),
                    ),
                  )
                : null,
            padding: editable
                ? const EdgeInsets.only(bottom: 3)
                : EdgeInsets.zero,
            child:
                valueWidget ??
                Text(
                  hasValue ? value! : (placeholder ?? ''),
                  textAlign: TextAlign.right,
                  style: t.bodyMedium?.copyWith(
                    fontWeight: hasValue ? FontWeight.w500 : FontWeight.w400,
                    color: hasValue
                        ? null
                        : (warnPlaceholder
                              ? AppColors.dangerFg
                              : Theme.of(context).disabledColor),
                  ),
                ),
          ),
        ),
        if (certainty.needsAttention) ...[
          const SizedBox(width: Gap.xs),
          Tooltip(
            message: certainty == Certainty.poor
                ? '거의 못 읽었습니다. 값이 맞는지 꼭 확인하세요.'
                : '읽긴 했는데 자신 없습니다. 확인해 주세요.',
            child: Icon(
              certainty == Certainty.poor
                  ? Icons.error_outline
                  : Icons.help_outline,
              size: 16,
              // 거의 못 읽은 것만 빨강이다. 둘을 같은 색으로 두면 정도가
              // 안 보이고, 빨강이 흔해지면 빨강이 무뎌진다.
              color: certainty == Certainty.poor
                  ? AppColors.dangerFg
                  : AppColors.noticeFg,
            ),
          ),
        ],
        if (trailing != null) ...[const SizedBox(width: Gap.sm), trailing!],
        if (onTap != null)
          Padding(
            padding: const EdgeInsets.only(left: Gap.xs),
            child: Icon(
              editable ? Icons.edit_outlined : Icons.chevron_right,
              size: editable ? 16 : 20,
              color: const Color(0xFFC2C2C7),
            ),
          ),
      ],
    );

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.lg,
          vertical: Gap.md,
        ),
        child: subtitle == null
            ? row
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  row,
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: t.bodySmall?.copyWith(color: AppColors.neutralFg),
                  ),
                ],
              ),
      ),
    );
  }
}

/// 탭하면 **그 자리가 입력칸**이 되는 줄.
///
/// ## 왜 다이얼로그를 버렸나
///
/// 예전엔 `promptText` 로 팝업을 띄웠다. 탭 → 팝업 → 입력 → 확인 → 닫힘,
/// 네 동작이고 그 사이 화면이 두 번 바뀐다. 한 줄짜리 값을 고치는 데 드는
/// 비용이 너무 컸다.
///
/// ## 저장 시점
///
/// **포커스를 잃으면 저장한다.** 완료 버튼을 눌러도 같다. 팝업의 `확인` 을
/// 대신하는 셈인데, 모바일에서는 다른 칸을 누르는 것이 곧 "이 칸은 끝났다" 다.
/// 취소 버튼을 두지 않는 이유는 그것 때문에 칸마다 버튼 두 개가 붙으면
/// 줄이 복잡해지기 때문이다 — OCR 이 읽은 값으로 되돌리는 길은
/// `OcrConflictNote` 의 칩이 따로 열어둔다.
///
/// ## 키보드
///
/// 포커스를 받으면 그 줄을 보이는 곳으로 스크롤한다. 검토 화면이 길어서
/// 아래쪽 칸은 키보드에 덮인다 — 덮인 채로 입력하면 자기가 뭘 쓰는지 안 보인다.
class InlineEditRow extends StatefulWidget {
  const InlineEditRow({
    required this.label,
    required this.onSubmit,
    super.key,
    this.value,
    this.placeholder,
    this.hintText,
    this.subtitle,
    this.keyboardType,
    this.warnPlaceholder = false,
    this.certainty = Certainty.unknown,
  });

  final String label;
  final String? value;
  final String? placeholder;

  /// 편집 중에만 보여줄 안내. 없으면 [placeholder] 를 쓴다.
  final String? hintText;

  final String? subtitle;
  final TextInputType? keyboardType;
  final bool warnPlaceholder;
  final Certainty certainty;

  /// 저장할 때 호출된다. 앞뒤 공백은 떼서 넘긴다.
  final ValueChanged<String> onSubmit;

  @override
  State<InlineEditRow> createState() => _InlineEditRowState();
}

class _InlineEditRowState extends State<InlineEditRow> {
  final _focus = FocusNode();
  TextEditingController? _controller;

  /// 저장이 두 번 불리는 것을 막는다. 완료를 누르면 `onSubmitted` 가 오고,
  /// 그 다음 포커스가 빠지면서 리스너도 울린다.
  bool _saving = false;

  bool get _editing => _controller != null;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocusChange)
      ..dispose();
    _controller?.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focus.hasFocus && _editing) _save();
  }

  void _begin() {
    setState(() {
      _controller = TextEditingController(text: widget.value ?? '')
        // 바로 고쳐 쓰는 경우가 많아서 **끝에 커서**를 둔다. 전체 선택으로
        // 두면 아무 글자나 누르는 순간 기존 값이 날아간다.
        ..selection = TextSelection.collapsed(
          offset: (widget.value ?? '').length,
        );
    });
    _focus.requestFocus();
    // 레이아웃이 바뀐 뒤에 스크롤해야 제자리를 찾는다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        context,
        // 줄을 화면 위쪽에 둬서 아래로 올라오는 키보드와 안 겹치게 한다.
        alignment: 0.2,
        duration: const Duration(milliseconds: 200),
      );
    });
  }

  void _save() {
    if (_saving) return;
    _saving = true;
    final text = _controller?.text.trim() ?? '';
    final c = _controller;
    setState(() => _controller = null);
    c?.dispose();
    _saving = false;
    if (text != (widget.value ?? '')) widget.onSubmit(text);
  }

  @override
  Widget build(BuildContext context) {
    if (!_editing) {
      return LabeledRow(
        label: widget.label,
        value: widget.value,
        placeholder: widget.placeholder,
        subtitle: widget.subtitle,
        warnPlaceholder: widget.warnPlaceholder,
        certainty: widget.certainty,
        editable: true,
        onTap: _begin,
      );
    }

    return LabeledRow(
      label: widget.label,
      subtitle: widget.subtitle,
      certainty: widget.certainty,
      editable: true,
      valueWidget: TextField(
        controller: _controller,
        focusNode: _focus,
        textAlign: TextAlign.right,
        keyboardType: widget.keyboardType,
        textInputAction: TextInputAction.done,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.zero,
          // 밑줄은 LabeledRow 가 그린다. 여기서 또 그리면 두 줄이 된다.
          border: InputBorder.none,
          hintText: widget.hintText ?? widget.placeholder,
          hintStyle: Theme.of(context).textTheme.bodySmall,
        ),
        onSubmitted: (_) => _focus.unfocus(),
      ),
    );
  }
}
