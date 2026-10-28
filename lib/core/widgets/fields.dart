/// 입력 필드.
///
/// 앱에서 글자를 직접 받는 곳은 많지 않다 — 대부분 OCR 이 채우거나 목록에서
/// 고른다. 그래서 필드도 두 종류뿐이다: 값을 고치는 것과 목록을 좁히는 것.
library;

import 'package:bodit_app/core/theme/tokens.dart';
import 'package:flutter/material.dart';

/// 값 하나를 고쳐 넣는 입력.
///

/// 목록을 좁히는 검색 입력.
///
/// 분류 44개처럼 스크롤로 찾기 번거로운 목록 위에 둔다.
class SearchField extends StatelessWidget {
  const SearchField({
    required this.hintText,
    required this.onChanged,
    this.autofocus = true,
    super.key,
  });

  final String hintText;
  final ValueChanged<String> onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextField(
      autofocus: autofocus,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(Icons.search, size: 20),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: Gap.md),
        border: const OutlineInputBorder(),
      ),
    );
  }
}

/// 줄 전체를 쓰는 **인플레이스 편집**. 파일명처럼 길고 고정폭으로 보여줘야
/// 하는 값에 쓴다.
///
/// `InlineEditRow` 와 역할은 같지만 모양이 다르다. 그쪽은 `라벨 … 값` 한 줄에
/// 값을 **우측 정렬**로 넣는데, 파일명은 화면 폭을 거의 다 쓰고 두 줄까지
/// 간다 — 우측 정렬 좁은 칸에 넣으면 앞부분이 안 보인다.
///
/// 저장은 `InlineEditRow` 와 같다: 포커스를 잃거나 버튼을 누르면 저장한다.
class InlineEditText extends StatefulWidget {
  const InlineEditText({
    required this.value,
    required this.onSubmit,
    super.key,
    this.maxLines = 2,
    this.monospace = false,
  });

  final String value;

  /// 저장할 때 호출된다. 앞뒤 공백은 떼서 넘긴다.
  ///
  /// **치환 규칙은 호출부가 적용한다** — 파일명의 `/` 하나로 Drive 동기화가
  /// 깨지는데, 그 규칙은 이 위젯이 알 일이 아니다.
  final ValueChanged<String> onSubmit;

  final int maxLines;

  /// 고정폭으로 보여준다. 파일명처럼 **글자 하나를 세어 읽는** 값에 쓴다.
  final bool monospace;

  @override
  State<InlineEditText> createState() => _InlineEditTextState();
}

class _InlineEditTextState extends State<InlineEditText> {
  final _focus = FocusNode();
  TextEditingController? _controller;
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
      _controller = TextEditingController(text: widget.value)
        ..selection = TextSelection.collapsed(offset: widget.value.length);
    });
    _focus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        context,
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
    if (text != widget.value) widget.onSubmit(text);
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall
        ?.copyWith(fontFamily: widget.monospace ? 'monospace' : null);

    return Padding(
      padding: const EdgeInsets.all(Gap.lg),
      child: Row(
        children: [
          Expanded(
            child: _editing
                ? TextField(
                    controller: _controller,
                    focusNode: _focus,
                    maxLines: widget.maxLines,
                    style: style,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: UnderlineInputBorder(),
                    ),
                  )
                : Text(widget.value, style: style),
          ),
          TextButton(
            onPressed: _editing ? _focus.unfocus : _begin,
            child: Text(_editing ? '완료' : '수정'),
          ),
        ],
      ),
    );
  }
}
