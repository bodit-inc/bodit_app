/// 업데이트 안내(다이얼로그)와 차단 화면이 **같이 쓰는 것들.**
///
/// 둘이 같은 말을 해야 한다 — 한쪽은 "1.0.1 받으세요", 다른 쪽은 "최신
/// 버전으로 올려주세요" 라고 적히면 같은 상황인지 알 수 없다.
library;

import 'package:bodit_app/models/app_update.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// TestFlight **앱 자체**를 여는 스킴.
///
/// ## 왜 앱까지만 가나
///
/// 앱 안의 "매입내역" 페이지로 바로 가는 링크는 `testflight.apple.com/join/…`
/// 하나뿐인데, 그건 **외부 테스터 그룹의 공개 링크**다 — 외부 그룹을 만들고
/// 빌드마다 베타 심사를 받아야 생긴다. 사내 배포는 내부 그룹이라 그 링크가
/// 없다. TestFlight 를 열어주고 목록에서 한 번 더 누르게 하는 쪽이, 아무
/// 데도 못 보내고 "열지 못했습니다" 를 띄우는 것보다 낫다.
///
/// ## 폴백이다 — 콘솔 값이 이긴다
///
/// 나중에 외부 그룹을 만들어 공개 링크가 생기면 `update_url_ios` 에 넣기만
/// 하면 된다. 코드를 고치지 않는다.
///
/// Android 에는 짝이 없다 — App Distribution 은 열어줄 앱이 아니라 웹 링크라,
/// 콘솔에 안 적으면 보낼 곳이 정말로 없다.
const testFlightUrl = 'itms-beta://';

/// 어디로 보낼지 정한다. 콘솔 값이 있으면 그것, 없으면 플랫폼 기본값.
/// 둘 다 없으면 null — 부르는 쪽이 "링크가 없다" 고 말한다.
@visibleForTesting
String? updateTargetUrl(AppUpdate update, TargetPlatform platform) {
  final fromConsole = update.url;
  if (fromConsole != null && fromConsole.isNotEmpty) return fromConsole;
  return platform == TargetPlatform.iOS ? testFlightUrl : null;
}

/// `1.0.0+5 → 1.0.1+6`. 한쪽이라도 모르면 빈 문자열이다.
///
/// **지금 버전을 같이 적는다.** 최신 버전만 적으면 이미 올린 사람도 같은
/// 안내를 다시 받았다고 느낀다 — 내 것이 몇인지가 판단의 절반이다.
String updateVersionLine(AppUpdate update) {
  final from = update.current;
  final to = update.latest;
  if (from == null || to == null) return '';
  return '$from → $to';
}

/// 받으러 간다. TestFlight(iOS) · App Distribution(Android) 으로 나간다.
///
/// 링크는 **원격 값**이라 비어 있거나 깨져 있을 수 있다. 그때 조용히 아무
/// 일도 안 일어나면 사용자는 버튼이 고장난 줄 안다 — 어디로 가야 하는지
/// 말로라도 알려준다.
Future<void> openUpdateLink(BuildContext context, AppUpdate update) async {
  final messenger = ScaffoldMessenger.of(context);
  final raw = updateTargetUrl(update, defaultTargetPlatform);
  final uri = raw == null ? null : Uri.tryParse(raw);

  if (uri == null || !uri.hasScheme) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('받는 곳 링크가 없습니다. TestFlight·App Distribution 에서 받아주세요.'),
      ),
    );
    return;
  }

  // 외부 앱이 받아간다 — iOS 는 TestFlight, Android 는 브라우저다
  // (홈의 시트·드라이브 바로가기와 같은 방식).
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok) {
    // iOS 에서 여기 오는 가장 흔한 경우는 **TestFlight 가 안 깔린 것**이다.
    // 열 앱이 없으면 스킴을 받아줄 데가 없다.
    messenger.showSnackBar(
      const SnackBar(
        content: Text('받는 곳을 열지 못했습니다. TestFlight 앱이 깔려 있는지 확인해 주세요.'),
      ),
    );
  }
}
