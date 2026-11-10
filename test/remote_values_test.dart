/// 한 번의 조회로 받아온 원격 값([RemoteValues])을 어떻게 해석하나.
///
/// 조회 자체(`RemoteConfigService.fetch`)는 Firebase 플러그인이라 여기서 못
/// 본다. 받아온 **뒤**의 순수 로직만 떼어내 고정한다.
library;

import 'package:bodit_app/data/remote/remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('빈 값', () {
    test('모든 칸이 빈 문자열이다 — 소비자 전부에게 "아무 일 없음" 이어야 한다', () {
      // 비행기 모드·Firebase 미설정·파라미터 오타가 전부 여기로 떨어진다.
      // 업데이트는 안내도 차단도 없고, Slack 은 구워진 명단만 쓴다.
      const v = RemoteValues.empty;
      expect(v.latest, '');
      expect(v.minimum, '');
      expect(v.message, '');
      expect(v.slackUserIds, '');
      expect(v.urlIos, '');
      expect(v.urlAndroid, '');
    });
  });

  group('받는 곳은 플랫폼마다 다르다', () {
    const v = RemoteValues(
      urlIos: 'itms-beta://x',
      urlAndroid: 'https://appdistribution/x',
    );

    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('iOS 는 TestFlight 쪽을 본다', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(v.updateUrl, 'itms-beta://x');
    });

    test('Android 는 App Distribution 쪽을 본다', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(v.updateUrl, 'https://appdistribution/x');
    });

    test('iOS 가 아닌 나머지는 Android 칸으로 떨어진다', () {
      // 데스크톱 타깃은 안 만들지만(ADR), 그렇다고 빈 값을 주면 안 된다 —
      // 둘 중 하나는 골라야 하고 받는 곳이 웹 링크인 쪽이 맞다.
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(v.updateUrl, 'https://appdistribution/x');
    });
  });

  group('파라미터 이름', () {
    test('콘솔에 적는 글자와 같다 — 틀리면 기본값이 나오고 조용히 틀린다', () {
      // 이 문자열이 바뀌면 콘솔의 파라미터도 같이 바꿔야 한다.
      // README "업데이트 알림" 표가 같은 이름을 적고 있다.
      expect(RemoteKeys.latest, 'latest_version');
      expect(RemoteKeys.minimum, 'minimum_version');
      expect(RemoteKeys.message, 'update_message');
      expect(RemoteKeys.urlIos, 'update_url_ios');
      expect(RemoteKeys.urlAndroid, 'update_url_android');
      expect(RemoteKeys.slackUserIds, 'slack_user_ids');
    });
  });
}
