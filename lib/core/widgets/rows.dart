/// 카드 안에 들어가는 줄.
///
/// 시안의 `.row` 가 여기 대응한다. 라벨 + 값 + (선택) 부가설명 + 우측 요소.
library;

import 'package:bodit_app/core/theme/tokens.dart';
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
          child: Text(
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
        if (trailing != null) ...[const SizedBox(width: Gap.sm), trailing!],
        if (onTap != null)
          const Padding(
            padding: EdgeInsets.only(left: Gap.xs),
            child: Icon(
              Icons.chevron_right,
              size: 20,
              color: Color(0xFFC2C2C7),
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
