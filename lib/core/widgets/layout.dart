/// 화면 뼈대 — 섹션과 카드.
///
/// 시안(`docs/mockup/`)의 `.sec` · `.card` 가 여기 대응한다.
library;

import 'package:bodit_app/core/theme/tokens.dart';
import 'package:bodit_app/core/widgets/app_widgets.dart' show LabeledRow;
import 'package:bodit_app/core/widgets/rows.dart' show LabeledRow;
import 'package:flutter/material.dart';

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
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
          padding: const EdgeInsets.symmetric(
            vertical: Gap.xl,
            horizontal: Gap.lg,
          ),
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
