/// 사용자에게 무언가 알리는 것들 — 보조설명·안내·실패.
///
/// 강도 순서: `NoteText`(지나가는 말) < `SuggestReason`(근거) <
/// `NoticeBanner`(확인 필요) < `ErrorDisclosure`(실패).
/// 강도를 올릴수록 색이 진해진다 — 아무거나 빨갛게 하면 진짜 실패가 안 보인다.
library;

import 'package:bodit_app/core/theme/tokens.dart';
import 'package:bodit_app/core/widgets/chips.dart';
import 'package:flutter/material.dart';

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
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: AppColors.neutralFg),
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
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: AppColors.successFg),
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
        // 문단이라 body 계열이다. 줄간격만 얹는다.
        style: Theme.of(context).textTheme.bodySmall!.copyWith(
          height: 1.5,
          color: dark ? Colors.white : AppColors.noticeFg,
        ),
        child: child,
      ),
    );
  }
}

/// 실패를 알리되 원문은 접어둔다. 누르면 펼쳐진다.
///
/// ## 이 앱의 에러 표시 규칙
///
/// 두 원칙이 충돌하는 지점이라 이렇게 정했다.
///
///   - **조용히 실패하면 안 된다** — 원인을 숨기면 사용자도 우리도 못 고친다
///   - 그런데 예외 원문은 대부분 `GoogleSignInException(code: ...)` 같은
///     **개발자용 영문 문자열**이다. 그대로 펼쳐두면 사용자는 못 읽는 한 덩어리를
///     보게 되고, 정작 눌러야 할 버튼이 화면 밖으로 밀려난다
///
/// 절충: **기본은 사람이 읽을 한 줄, 누르면 전문.**
/// 사용자는 한 줄만 보고, 원인을 물어볼 때 펼쳐서 읽어주면 된다.
///
/// 원문은 고정폭 + 선택 가능이다 — 복사해서 붙여넣고 물어볼 수 있어야 한다.
///
/// 새 에러 표시를 만들 때 예외를 `Text('$e')` 로 그냥 뿌리지 말고 이걸 쓴다.
/// (예외: 스낵바처럼 **사라지는** 알림. 접을 대상이 아니다.)
class ErrorDisclosure extends StatefulWidget {
  const ErrorDisclosure(
    this.message, {
    required this.detail,
    this.align = MainAxisAlignment.center,
    super.key,
  });

  /// 사람이 읽을 한 줄. "로그인에 실패했습니다." 처럼.
  final String message;

  /// 예외 원문. 펼쳤을 때만 보인다.
  final String detail;

  /// 목록 안에 놓을 때는 왼쪽 정렬이 자연스럽다.
  final MainAxisAlignment align;

  @override
  State<ErrorDisclosure> createState() => _ErrorDisclosureState();
}

class _ErrorDisclosureState extends State<ErrorDisclosure> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 화살표가 "누를 수 있다" 는 유일한 신호다. 빼면 아무도 안 누른다.
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(Radii.button),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.sm,
              vertical: Gap.xs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: widget.align,
              children: [
                Flexible(
                  child: Text(
                    widget.message,
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: error, fontWeight: FontWeight.w400),
                  ),
                ),
                const SizedBox(width: Gap.xs),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(Icons.expand_more, size: 18, color: error),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 150),
          crossFadeState: _expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: Gap.sm),
            padding: const EdgeInsets.all(Gap.md),
            decoration: BoxDecoration(
              color: error.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(Radii.card),
            ),
            // 개발자용 문자열이라 고정폭이 읽기 낫다.
            // 붙여넣어 물어볼 수 있게 선택도 가능하게 둔다.
            child: SelectableText(
              widget.detail,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// OCR 이 읽은 값과 **다르게 고쳤을 때**의 안내 + 되돌리기 칩.
///
/// 입력 칸 **바로 아래**에 붙인다. 제출 직전에 몰아서 알려주면 어느 칸이었는지
/// 다시 찾아야 하고, 그러면 아무도 안 본다.
///
/// ## 왜 막지 않고 알리기만 하나
///
/// 고치는 쪽이 맞는 경우가 많다 — OCR 이 상호를 잘못 읽는 일은 흔하다.
/// 그래서 **값을 되돌리지 않고** "이렇게 읽었다" 만 말하고, 되돌릴 길을
/// 칩으로 열어둔다. 사용자가 둘 중 하나를 고른다.
///
/// ## 왜 danger 가 아닌가
///
/// 사용자가 **의도적으로** 고친 것일 수 있다. 빨갛게 띄우면 정당한 수정마다
/// 오류처럼 보이고, 빨강이 흔해지면 진짜 실패가 안 보인다.
class OcrConflictNote extends StatelessWidget {
  const OcrConflictNote({
    required this.ocrValue,
    required this.onRevert,
    super.key,
  });

  /// OCR 이 읽은 값. **사람이 읽을 형태로 포맷해서** 넘긴다 — 날짜·금액의
  /// 표기는 화면이 이미 갖고 있다.
  final String ocrValue;

  /// 칩을 누르면 그 값으로 되돌린다.
  final VoidCallback onRevert;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '"$ocrValue" 로 인식했습니다. 다시 확인해주세요.',
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: AppColors.noticeFg),
          ),
          const SizedBox(height: Gap.sm),
          SuggestChip(ocrValue, onTap: onRevert),
        ],
      ),
    );
  }
}
