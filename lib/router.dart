import 'package:bodit_app/features/auth/sign_in_screen.dart';
import 'package:bodit_app/features/home/home_screen.dart';
import 'package:bodit_app/features/review/review_screen.dart';
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
  static const signIn = '/sign-in';
  static const home = '/';
  static const review = '/review';
  static const submissions = '/submissions';
}

GoRouter buildRouter({required bool Function() isSignedIn}) {
  return GoRouter(
    initialLocation: Routes.home,
    redirect: (context, state) {
      final signedIn = isSignedIn();
      final atSignIn = state.matchedLocation == Routes.signIn;
      if (!signedIn && !atSignIn) return Routes.signIn;
      if (signedIn && atSignIn) return Routes.home;
      return null;
    },
    routes: [
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
