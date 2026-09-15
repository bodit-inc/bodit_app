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
                Text(
                  '로그인에 실패했습니다.\n${auth.error}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
