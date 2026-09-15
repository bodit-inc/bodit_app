/// 입력 필드.
///
/// 앱에서 글자를 직접 받는 곳은 많지 않다 — 대부분 OCR 이 채우거나 목록에서
/// 고른다. 그래서 필드도 두 종류뿐이다: 값을 고치는 것과 목록을 좁히는 것.
library;

import 'package:bodit_app/core/theme/tokens.dart';
import 'package:flutter/material.dart';

/// 값 하나를 고쳐 넣는 입력.
///
/// 다이얼로그 안에서 쓴다. 열자마자 커서가 들어가고 기존 값이 **전체 선택**된
/// 상태다 — 고치러 들어온 것이지 이어 쓰려는 게 아니다.
class AppTextField extends StatefulWidget {
  const AppTextField({
    required this.controller,
    this.hintText,
    this.keyboardType,
    this.maxLines = 1,
    this.autofocus = true,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final String? hintText;
  final TextInputType? keyboardType;
  final int maxLines;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  @override
  void initState() {
    super.initState();
    // 기존 값을 통째로 선택해 둔다. 바로 타이핑하면 덮어써진다.
    widget.controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.controller.text.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      autofocus: widget.autofocus,
      keyboardType: widget.keyboardType,
      maxLines: widget.maxLines,
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        hintText: widget.hintText,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

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
