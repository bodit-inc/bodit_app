import 'package:bodit_app/core/theme/tokens.dart';
import 'package:bodit_app/features/auth/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 시안 ① — 설명 없이 Google 로그인만.
class SignInScreen extends ConsumerWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🧾', style: TextStyle(fontSize: 46)),
              const SizedBox(height: Gap.lg),
              Text('매입내역', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 56),
              if (auth.isLoading)
                const CircularProgressIndicator()
              else
                OutlinedButton.icon(
                  onPressed: () =>
                      ref.read(authControllerProvider.notifier).signIn(),
                  icon: const Text('G',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  label: const Text('Google 계정으로 로그인'),
                ),
              // 재시도 중에도 AsyncValue 는 직전 에러를 들고 있다.
              // `isLoading` 을 같이 보지 않으면 스피너와 에러 문구가 동시에 뜬다.
              //
              // 그리고 여기 뜨는 건 **사용자가 버튼을 눌러서 난 실패**뿐이다.
              // 앱 시작 시의 조용한 복구 실패는 `GoogleAuthService.restore()` 가
              // 삼키고 로그로만 남긴다 — 아무도 시도하지 않은 실패를 보여주면 안 된다.
              if (auth.hasError && !auth.isLoading) ...[
                const SizedBox(height: Gap.lg),
                // 에러 원문은 접어둔다. 자세한 내용은 눌러야 나온다.
                _ExpandableError('${auth.error}'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}


/// 실패 문구를 누르면 원인이 펼쳐진다.
///
/// ## 왜 접어두나
///
/// 여기 뜨는 에러는 대부분 `GoogleSignInException(code: ..., serverClientId
/// must be provided on Android, null)` 같은 **개발자용 문자열**이다.
/// 로그인 화면에 그대로 펼쳐두면 사용자는 읽지도 못하는 영문 한 덩어리를 보게 되고,
/// 정작 눌러야 할 로그인 버튼이 밀려난다.
///
/// 그렇다고 숨기면 안 된다 — "조용히 실패하면 안 된다" 는 이 앱의 원칙이다.
/// 그래서 **기본은 한 줄, 원하면 펼쳐서 전문**으로 둔다.
/// 사용자는 한 줄만 보고, 원인을 물어볼 때 펼쳐서 읽어주면 된다.
///
/// 펼침 상태는 이 위젯만 들고 있다. 화면 전체를 Stateful 로 만들지 않으려고
/// 여기로 뺐다.
class _ExpandableError extends StatefulWidget {
  const _ExpandableError(this.detail);

  /// 예외 원문. 사용자가 펼쳤을 때만 보인다.
  final String detail;

  @override
  State<_ExpandableError> createState() => _ExpandableErrorState();
}

class _ExpandableErrorState extends State<_ExpandableError> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: error,
          fontWeight: FontWeight.w400,
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 누를 수 있다는 걸 알려야 한다 — 화살표가 그 신호다.
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
              children: [
                Text('로그인에 실패했습니다.', style: labelStyle),
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
          crossFadeState:
              _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: Gap.sm),
            padding: const EdgeInsets.all(Gap.md),
            decoration: BoxDecoration(
              color: error.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(Radii.card),
            ),
            child: SelectableText(
              widget.detail,
              // 개발자용 문자열이라 고정폭이 읽기 낫다.
              // 붙여넣어 물어볼 수 있게 선택도 가능하게 둔다.
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
      ],
    );
  }
}
