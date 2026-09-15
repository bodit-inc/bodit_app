import 'package:bodit_app/core/theme/app_theme.dart';
import 'package:bodit_app/features/auth/auth_controller.dart';
import 'package:bodit_app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 라우터는 인증 상태를 읽어야 하므로 provider 로 만든다.
final routerProvider = Provider<GoRouter>((ref) {
  return buildRouter(
    // Riverpod 3 에서 `valueOrNull` 이 없어지고 `value` 가 널 가능이 됐다.
    isSignedIn: () => ref.read(authControllerProvider).value != null,
    // 로딩 중 = 조용한 복구가 아직 안 끝났다. 그동안은 스플래시에 머문다.
    isRestoring: () => ref.read(authControllerProvider).isLoading,
  );
});

class BoditApp extends ConsumerStatefulWidget {
  const BoditApp({super.key});

  @override
  ConsumerState<BoditApp> createState() => _BoditAppState();
}

class _BoditAppState extends ConsumerState<BoditApp> {
  @override
  Widget build(BuildContext context) {
    // 인증 상태를 지켜본다 — 복구가 끝나면 라우터가 스플래시에서 내보낸다.
    ref.watch(authControllerProvider);

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
