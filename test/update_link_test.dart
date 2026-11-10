/// 업데이트 버튼이 **어디로 보내는지.**
///
/// 여는 일 자체(`launchUrl`)는 플랫폼 채널이라 여기서 못 본다. 그 앞의
/// "어느 주소를 고르나" 만 떼어내 고정한다.
library;

import 'package:bodit_app/core/version.dart';
import 'package:bodit_app/features/update/update_prompt.dart';
import 'package:bodit_app/models/app_update.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AppUpdate withUrl(String? url) => AppUpdate(
    urgency: UpdateUrgency.optional,
    current: AppVersion.tryParse('1.0.0+5'),
    latest: AppVersion.tryParse('1.0.1'),
    url: url,
  );

  test('콘솔 값이 있으면 그것이 이긴다 — 공개 링크가 생기면 코드를 안 고친다', () {
    final u = withUrl('https://testflight.apple.com/join/abcd');
    expect(
      updateTargetUrl(u, TargetPlatform.iOS),
      'https://testflight.apple.com/join/abcd',
    );
    expect(
      updateTargetUrl(u, TargetPlatform.android),
      'https://testflight.apple.com/join/abcd',
    );
  });

  test('iOS 는 콘솔 값이 없으면 TestFlight 앱을 연다', () {
    expect(updateTargetUrl(withUrl(null), TargetPlatform.iOS), testFlightUrl);
  });

  test('Android 는 폴백이 없다 — 열어줄 앱이 아니라 웹 링크라서다', () {
    expect(updateTargetUrl(withUrl(null), TargetPlatform.android), isNull);
  });

  test('스킴에 `://` 까지 붙어 있어야 한다 — 이름만 적으면 안 열린다', () {
    // Info.plist 의 조회 목록에는 반대로 **이름만** 적는다. 두 자리가
    // 다르다는 것을 여기 박아둔다.
    expect(testFlightUrl, 'itms-beta://');
    expect(Uri.parse(testFlightUrl).hasScheme, isTrue);
  });
}
