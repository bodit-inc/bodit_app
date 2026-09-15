/// 반복되는 버튼 조합.
///
/// Material 버튼을 통째로 감싸지 않는다 — 기본 모양은 `AppTheme` 이 정하고,
/// 여기에는 **같은 조합이 두 번 이상 나온 것**만 둔다. 한 번뿐인 버튼까지
/// 이름을 붙이면 이름만 늘고 읽기는 더 어려워진다.
library;

import 'package:bodit_app/core/theme/tokens.dart';
import 'package:flutter/material.dart';

/// 실패한 것을 다시 불러오는 버튼.
///
/// 비목·분류 선택 시트 양쪽에서 같은 모양으로 쓰인다. 실패 화면에는
/// 원인(`ErrorDisclosure`)과 이 버튼이 함께 있어야 한다 — 원인만 보여주고
/// 다시 할 방법이 없으면 앱을 껐다 켜야 한다.
class RetryButton extends StatelessWidget {
  const RetryButton({required this.onPressed, this.label = '다시 시도', super.key});

  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.refresh, size: 18),
      label: Text(label),
    );
  }
}

/// 되돌릴 수 없는 동작의 버튼. 글자가 빨갛다.
///
/// 다이얼로그의 [지우기] 처럼 **누르면 끝나는** 자리에만 쓴다.
/// 아무 데나 빨갛게 하면 정작 위험한 곳이 눈에 안 띈다.
class DangerTextButton extends StatelessWidget {
  const DangerTextButton({
    required this.onPressed,
    required this.label,
    super.key,
  });

  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(foregroundColor: AppColors.danger),
      child: Text(label),
    );
  }
}

/// 카드·배너 안에 들어가는 작은 보조 버튼.
///
/// 기본 높이(48)가 배너 안에서는 너무 크다. 부가세 [1.1로 나누기] 처럼
/// 본문 흐름에 끼어드는 자리에 쓴다.
class InlineButton extends StatelessWidget {
  const InlineButton({required this.onPressed, required this.label, super.key});

  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: Gap.md),
      ),
      child: Text(label),
    );
  }
}
