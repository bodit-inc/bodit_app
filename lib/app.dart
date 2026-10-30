import 'package:bodit_app/core/flavor.dart';
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
      // 작업 전환 화면에 뜨는 이름. 개발 빌드는 여기서도 갈려 보여야 한다.
      title: isDevFlavor ? '매입내역(개발)' : '매입내역',
      theme: AppTheme.light,
      routerConfig: ref.watch(routerProvider),
      debugShowCheckedModeBanner: false,
      // 개발 빌드는 **어느 화면에서도** 개발인 줄 알아야 한다.
      //
      // 홈의 안내 배너만으로는 모자라다 — 검토 폼에서 바로 제출하면 홈을 안
      // 거치고, 그러면 "운영에 보낸 줄 알았는데 개발이었다"(또는 그 반대)가
      // 된다. 리본은 라우터 바깥에 있어서 모든 화면 위에 남는다.
      //
      // `debugShowCheckedModeBanner` 와 다른 것이다 — 그건 release 빌드에서
      // 사라지는데, 개발 환경을 release 로도 빌드하기 때문이다.
      builder: (context, child) {
        if (!isDevFlavor || child == null) return child ?? const SizedBox();
        return Banner(
          message: 'DEV',
          location: BannerLocation.topEnd,
          child: child,
        );
      },
    );
  }
}
