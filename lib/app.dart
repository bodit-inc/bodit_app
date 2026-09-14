import 'package:bodit_app/core/router/app_router.dart';
import 'package:bodit_app/core/theme/app_theme.dart';
import 'package:bodit_app/features/auth/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 라우터는 인증 상태를 읽어야 하므로 provider 로 만든다.
final routerProvider = Provider<GoRouter>((ref) {
  return buildRouter(
    // Riverpod 3 에서 `valueOrNull` 이 없어지고 `value` 가 널 가능이 됐다.
    isSignedIn: () => ref.read(authControllerProvider).value != null,
  );
});

class BoditApp extends ConsumerWidget {
  const BoditApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 인증 상태가 바뀌면 라우터가 redirect 를 다시 평가하도록 강제한다.
    ref.listen(authControllerProvider, (_, _) {
      ref.read(routerProvider).refresh();
    });

    return MaterialApp.router(
      title: '매입내역',
      theme: AppTheme.light,
      routerConfig: ref.watch(routerProvider),
      debugShowCheckedModeBanner: false,
    );
  }
}
