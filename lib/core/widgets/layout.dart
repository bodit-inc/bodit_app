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
///
/// **줄 사이 구분선은 카드가 그리지 않는다.** 화면이 [RowDivider] 를 직접
/// 넣는다 — 예전엔 카드가 자식 사이에 자동으로 끼웠는데, 그러면 어떤 줄
/// 뒤에 선이 있는지가 화면 코드에 안 보였다. 조건부로 나오는 줄(되돌리기
/// 안내·경고)이 섞이면 더 그렇다.
class AppCard extends StatelessWidget {
  const AppCard({required this.children, super.key, this.color});

  final List<Widget> children;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      // 행이 카드 바깥(둥근 모서리)으로 색을 흘리지 않게 자른다.
      // 미는 삭제 배경(빨강)과 강조된 행이 첫·마지막 행에서 모서리를
      // 네모로 덮어버렸다 — 카드가 깨져 보인다.
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// [AppCard] 안, 줄 사이의 구분선.
///
/// **넣는 규칙은 하나다 — 첫 줄을 뺀 각 줄 앞에 하나.** 조건부로 나오는 줄은
/// 자기 구분선을 자기 조건 안에 들고 있는다:
///
/// ```dart
/// LabeledRow(label: '소속날짜', ...),
/// if (draft.belongDateOcrConflict != null) ...[
///   const RowDivider(),
///   OcrConflictNote(...),
/// ],
/// const RowDivider(),
/// LabeledRow(label: '지출날짜', ...),
/// ```
///
/// 그래야 그 줄이 안 나올 때 선도 같이 사라진다. 뒤에 붙이는 규칙으로 하면
/// 마지막 줄이 조건부일 때 카드 밑에 선만 남는다.
class RowDivider extends StatelessWidget {
  const RowDivider({this.indent = true, super.key});

  final bool indent;

  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    indent: indent ? Gap.lg : 0,
    endIndent: indent ? Gap.lg : 0,
  );
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
