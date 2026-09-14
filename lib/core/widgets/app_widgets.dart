import 'package:bodit_app/core/theme/tokens.dart';
import 'package:flutter/material.dart';

// 시안(`docs/mockup/`)의 CSS 에 이미 드러난 반복 패턴을 위젯으로 뽑은 것.
// .sec / .card+.row / .pill / .btn / .big / .chip / .note 가 각각 아래에 대응한다.
// 화면 코드는 이 위젯들만 조립한다 — 색·간격을 직접 쓰지 않는다.

/// 섹션 제목. 시안의 `.sec`
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.xs, Gap.lg, Gap.xs, Gap.sm),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.neutralFg,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
      ),
    );
  }
}

/// 흰 카드. 안에 [LabeledRow] 들을 넣는다. 시안의 `.card`
class AppCard extends StatelessWidget {
  const AppCard({required this.children, super.key, this.color});

  final List<Widget> children;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    // 마지막 행의 구분선은 그리지 않는다.
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i != children.length - 1) {
        rows.add(const Divider(height: 1, indent: Gap.lg, endIndent: Gap.lg));
      }
    }
    return Card(
      color: color,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
    );
  }
}

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
  });

  final String label;
  final String? value;

  /// 값 아래에 붙는 작은 설명 줄. 전송 진행 상태·실패 사유처럼
  /// **한 줄로 안 끝나는 정보**를 담는다.
  final String? subtitle;

  /// 값이 비었을 때 회색으로 보여줄 안내 문구.
  final String? placeholder;
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
                  color: hasValue ? null : Theme.of(context).disabledColor,
                ),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: Gap.sm), trailing!],
            if (onTap != null)
              const Padding(
                padding: EdgeInsets.only(left: Gap.xs),
                child: Icon(Icons.chevron_right, size: 20, color: Color(0xFFC2C2C7)),
              ),
          ],
        );

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
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
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: fg, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// 홈의 큰 액션 버튼(촬영 / 파일 선택). 시안의 `.big`
class BigActionCard extends StatelessWidget {
  const new({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.card),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Gap.xl, horizontal: Gap.lg),
          child: Column(
            children: [
              Icon(icon, size: 32),
              const SizedBox(height: Gap.sm),
              Text(title, style: t.titleSmall),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: t.bodySmall?.copyWith(color: AppColors.neutralFg),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
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
        padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
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

/// 추천의 **근거**. 근거 없이 채워두면 사용자가 못 믿고 전부 다시 확인한다.
class SuggestReason extends StatelessWidget {
  const new(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Gap.xs, left: 2),
      child: Text(
        '✓ $text',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: AppColors.successFg),
      ),
    );
  }
}

/// 카드 아래 작은 설명. 시안의 `.note`
class NoteText extends StatelessWidget {
  const new(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, 0),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: AppColors.neutralFg),
      ),
    );
  }
}

/// 안내 배너 (부가세 확인, 오프라인 안내 등). 시안의 `.banner`
class NoticeBanner extends StatelessWidget {
  const new({required this.child, super.key, this.dark = false});

  final Widget child;

  /// 오프라인 배너처럼 어두운 톤이 필요할 때.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.md),
      decoration: BoxDecoration(
        color: dark ? AppColors.offlineBg : AppColors.noticeBg,
        border: dark ? null : Border.all(color: AppColors.noticeBorder),
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(
          fontSize: 13,
          height: 1.5,
          color: dark ? Colors.white : AppColors.noticeFg,
        ),
        child: child,
      ),
    );
  }
}
