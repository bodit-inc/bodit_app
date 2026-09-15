import 'package:bodit_app/features/auth/sign_in_screen.dart';
import 'package:bodit_app/features/home/home_screen.dart';
import 'package:bodit_app/features/review/review_screen.dart';
import 'package:bodit_app/features/splash/splash_screen.dart';
import 'package:bodit_app/features/submissions/submissions_screen.dart';
import 'package:go_router/go_router.dart';

/// 화면 라우팅.
///
/// **`core/` 가 아니라 앱 조립 계층에 둔다.** `core` 는 "기능을 모르는 층" 인데
/// 라우터는 화면 전부를 알아야 하므로 거기 두면 의존 방향이 깨진다.
/// `app.dart` 옆이 제자리다.
///
/// 화면 수가 적어 `go_router` 로 충분하다.
///
/// 시안(`docs/mockup/`) 13장 중 독립 화면은 4개다 — 나머지는 같은 화면의
/// 다른 상태(로딩·다건·바텀시트)라 라우트를 나누지 않는다.
abstract final class Routes {
  /// 조용한 로그인 복구가 끝날 때까지 머무는 곳.
  static const splash = '/splash';
  static const signIn = '/sign-in';
  static const home = '/';
  static const review = '/review';
  static const submissions = '/submissions';
}

GoRouter buildRouter({
  required bool Function() isSignedIn,
  required bool Function() isRestoring,
}) {
  return GoRouter(
    initialLocation: Routes.splash,
    redirect: (context, state) {
      final at = state.matchedLocation;

      // 복구가 끝나기 전에는 어디로 갈지 알 수 없다. 스플래시에 머문다 —
      // 로그인 화면을 먼저 띄웠다가 홈으로 튕기면 화면이 두 번 바뀐다.
      if (isRestoring()) return at == Routes.splash ? null : Routes.splash;

      final signedIn = isSignedIn();
      if (!signedIn) return at == Routes.signIn ? null : Routes.signIn;
      // 복구가 끝났는데 아직 스플래시·로그인에 있으면 홈으로.
      if (at == Routes.splash || at == Routes.signIn) return Routes.home;
      return null;
    },
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: Routes.signIn, builder: (_, _) => const SignInScreen()),
      GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen()),
      GoRoute(path: Routes.review, builder: (_, _) => const ReviewScreen()),
      GoRoute(
        path: Routes.submissions,
        builder: (_, _) => const SubmissionsScreen(),
      ),
    ],
  );
}
