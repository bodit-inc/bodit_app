import 'package:bodit_app/core/flavor.dart';
import 'package:bodit_app/core/theme/app_theme.dart';
import 'package:bodit_app/data/background_send.dart';
import 'package:bodit_app/features/auth/auth_controller.dart';
import 'package:bodit_app/features/update/update_gate.dart';
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
  /// 전송 결과 스낵바를 띄울 곳.
  ///
  /// 전송이 백그라운드로 돌기 때문에 **결과가 도착할 때 사용자가 어느 화면에
  /// 있을지 모른다** — 홈일 수도, 다음 영수증의 검토 폼일 수도, 목록일 수도
  /// 있다. 그래서 특정 화면의 messenger 를 잡아두지 않고 앱 전체가 공유하는
  /// 하나에 띄운다.
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  Widget build(BuildContext context) {
    // 인증 상태를 지켜본다 — 복구가 끝나면 라우터가 스플래시에서 내보낸다.
    ref.watch(authControllerProvider);

    // 인증 상태가 바뀌면 라우터가 redirect 를 다시 평가하도록 강제한다.
    ref.listen(authControllerProvider, (_, _) {
      ref.read(routerProvider).refresh();
    });

    // 백그라운드 전송이 끝나면 결과를 말한다. **조용히 끝내면 안 된다** —
    // 제출하고 홈으로 돌아온 사용자는 띠가 사라진 것만 보고 성공했다고
    // 믿는다. 실패한 건은 전송 대기로 남아 있는데 아무도 안 본다.
    ref.listen(backgroundSendProvider, (_, next) {
      final report = next.report;
      if (report == null) return;
      // 읽었다고 알린다. 안 지우면 화면이 다시 그려질 때마다 또 뜬다.
      ref.read(backgroundSendProvider.notifier).consumeReport();
      // 보낼 게 없었으면(그 사이 목록에서 지웠다) 말할 것도 없다.
      if (report.total == 0) return;
      _messengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(_sendMessage(report)),
          duration: const Duration(seconds: 6),
        ),
      );
    });

    return MaterialApp.router(
      scaffoldMessengerKey: _messengerKey,
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
        // 쓰면 안 되는 버전은 여기서 막는다 — **라우터보다 위**라 어떤
        // 화면으로도 들어가지 못한다(`UpdateGate` 주석). 평소에는 아무것도
        // 하지 않고 `child` 를 그대로 흘린다.
        final gated = UpdateGate(child: child ?? const SizedBox());
        if (!isDevFlavor) return gated;
        // DEV 리본은 차단 화면 위에도 남아야 한다 — 그래서 가장 바깥이다.
        return Banner(
          message: 'DEV',
          location: BannerLocation.topEnd,
          child: gated,
        );
      },
    );
  }
}

/// 전송 결과 한 줄.
///
/// **어디가** 실패했는지만 적는다. 목적지가 독립이라 한 건에서 둘이 동시에
/// 실패할 수 있는데, 예외 원문을 그대로 깔면 접을 수 없는 스낵바가 화면
/// 절반을 덮는다 — 원문은 목록의 [실패 사유 보기] 가 맡는다.
String _sendMessage(SendReport report) {
  if (report.allSent) return '${report.sent}건을 전송했습니다.';
  final where = report.failedWhere;
  final tail = '${where == null ? '' : ' ($where)'} — 내 제출에서 사유를 볼 수 있습니다.';
  if (report.sent == 0) return '${report.failed}건을 전송하지 못했습니다$tail';
  return '${report.sent}건 전송, ${report.failed}건 실패$tail';
}
