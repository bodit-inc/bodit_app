/// 칩 — 상태·추천·목적지를 한 눈에 보여주는 작은 조각.
///
/// 공통 규칙: **바탕은 옅게, 글자는 진하게.** 칩이 색 덩어리로 보이면
/// 정작 읽어야 할 값보다 눈에 먼저 들어온다.
library;

import 'package:bodit_app/core/theme/tokens.dart';
import 'package:flutter/material.dart';

/// 전송 상태 표시. 시안의 `.pill`
enum PillTone { ok, waiting, error }

class StatusPill extends StatelessWidget {
  const new(this.label, {required this.tone, super.key});

  final String label;
  final PillTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      PillTone.ok => (AppColors.successBg, AppColors.successFg),
      PillTone.waiting => (AppColors.neutralBg, AppColors.neutralFg),
      PillTone.error => (AppColors.dangerBg, AppColors.dangerFg),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: fg, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// 과거 이력 기반 추천 칩. 시안의 `.chip`
///
/// [selected] 가 true 면 "이걸로 채워뒀다" 는 뜻이다.
class SuggestChip extends StatelessWidget {
  const new(
    this.label, {
    required this.onTap,
    super.key,
    this.selected = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.pill),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.md,
          vertical: Gap.sm,
        ),
        decoration: BoxDecoration(
          color: selected ? AppColors.suggestBg : AppColors.neutralBg,
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: selected ? AppColors.suggestFg : AppColors.neutralFg,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            if (selected) ...[
              const SizedBox(width: Gap.xs),
              const Icon(Icons.check, size: 15, color: AppColors.suggestFg),
            ],
          ],
        ),
      ),
    );
  }
}
