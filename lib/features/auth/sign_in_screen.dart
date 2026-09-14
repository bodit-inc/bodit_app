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
              if (auth.hasError) ...[
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
