/// Firebase Remote Config 를 **한 번 조회하고 여러 소비자가 나눠 쓴다.**
///
/// ## 왜 조회를 한 곳으로 모았나
///
/// 처음에는 `AppUpdateService` 안에 Firebase 초기화·조회·판정이 다 있었다.
/// 용도가 하나였으니(새 버전 확인) 나누면 쓰지도 않는 층이 하나 생기는
/// 상태였다. 그 파일 주석에 "두 번째 용도가 붙으면 그때 밖으로 뺀다" 고
/// 적어뒀고, **지금이 그때다** — Slack 멘션 매핑이 두 번째 소비자다.
///
/// 조회를 소비자마다 두면 앱이 켤 때 `fetchAndActivate` 가 두 번 나가고,
/// 운영의 `minimumFetchInterval`(1시간) 때문에 **둘이 서로 다른 시점의 값**을
/// 보게 된다. 받는 곳이 하나여야 한다.
///
/// ## 실패하면 빈 값을 돌려준다 (던지지 않는다)
///
/// 비행기 모드·Firebase 설정 미입력·파라미터 오타 — 전부 "원격 값을 모른다"
/// 로 끝나야 한다. 그래서 [RemoteValues.empty] 를 돌려주고, 그 빈 값이 곧
/// 각 소비자의 "아무 일 없음" 이다:
///
///   - 업데이트: 안내도 차단도 없음(`AppUpdate.none`)
///   - Slack 멘션: `.env` 에 구워진 명단만 쓴다
///
/// `ensureConfigured()` 가 Firebase 값을 막지 않는 것과 같은 규칙이다
/// (`core/config.dart` 의 "Firebase" 주석).
library;

import 'package:bodit_app/core/config.dart';
import 'package:bodit_app/core/flavor.dart';
import 'package:bodit_app/core/log.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

/// Remote Config 파라미터 이름. **콘솔에 적은 글자와 한 글자도 달라선 안 된다** —
/// 틀리면 기본값(빈 문자열)이 나오고, 그건 "값을 안 넣었다" 와 구분되지 않는다.
abstract final class RemoteKeys {
  /// 최신 버전. `1.0.1+6` 꼴. 비면 안내하지 않는다.
  static const latest = 'latest_version';

  /// 이 버전보다 낮으면 **쓰지 못한다.** 비면 아무도 막지 않는다.
  ///
  /// 보통은 비워둔다. 잘못 쓰는 버전을 즉시 세워야 할 때만 채운다.
  static const minimum = 'minimum_version';

  /// 안내에 같이 띄울 한 줄. 무엇이 바뀌었는지 적는다.
  static const message = 'update_message';

  /// 받으러 갈 곳. 플랫폼마다 다르다(TestFlight ↔ App Distribution).
  static const urlIos = 'update_url_ios';
  static const urlAndroid = 'update_url_android';

  /// 이메일 → Slack user id 매핑. `email:ID` 를 쉼표로 잇는다.
  ///
  /// **왜 원격 값인가** — 입사자가 생길 때마다 `.env` 를 고치고 `make gen` 을
  /// 돌려 **재배포**해야 그 사람 멘션이 붙었다. 멘션 한 줄 때문에 전원이
  /// 새 빌드를 받는 건 비싸다. `latest_version` 과 같은 이유로 원격이다 —
  /// 콘솔에서 한 줄 고치면 끝나야 하는 값이다.
  ///
  /// `.env` 의 `SLACK_USER_IDS` 를 **대체하지 않고 덮는다** — 아래
  /// `SlackRepository` 의 두 겹 설명 참고.
  static const slackUserIds = 'slack_user_ids';
}

/// 한 번의 조회로 받아온 원격 값들. **문자열 그대로 들고 있는다** —
/// 해석(버전 파싱·매핑 파싱)은 각 소비자가 한다.
@immutable
class RemoteValues {
  const RemoteValues({
    this.latest = '',
    this.minimum = '',
    this.message = '',
    this.urlIos = '',
    this.urlAndroid = '',
    this.slackUserIds = '',
  });

  /// 조회하지 못했을 때의 값. **모든 소비자에게 "아무 일 없음" 이어야 한다.**
  static const empty = RemoteValues();

  final String latest;
  final String minimum;
  final String message;
  final String urlIos;
  final String urlAndroid;
  final String slackUserIds;

  /// 플랫폼에 맞는 받는 곳. iOS 는 TestFlight, 그 외는 App Distribution.
  String get updateUrl => switch (defaultTargetPlatform) {
    TargetPlatform.iOS => urlIos,
    _ => urlAndroid,
  };
}

class RemoteConfigService {
  const RemoteConfigService();

  /// 원격 값을 받아온다. **던지지 않는다** — 못 받으면 [RemoteValues.empty].
  Future<RemoteValues> fetch() async {
    final options = _options();
    if (options == null) {
      log.i('Firebase 설정이 비어 있어 원격 설정을 건너뜁니다. (.env 의 FIREBASE_*)');
      return RemoteValues.empty;
    }

    try {
      // hot restart 하면 이미 초기화돼 있다. 또 부르면 duplicate-app 으로 던진다.
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: options);
      }
      final remote = FirebaseRemoteConfig.instance;

      // 기본값을 먼저 깐다. **전부 빈 문자열 = 아무 일 없음** — 조회가 늦거나
      // 실패했을 때 나오는 값이 그래야 한다.
      await remote.setDefaults(const {
        RemoteKeys.latest: '',
        RemoteKeys.minimum: '',
        RemoteKeys.message: '',
        RemoteKeys.urlIos: '',
        RemoteKeys.urlAndroid: '',
        RemoteKeys.slackUserIds: '',
      });

      await remote.setConfigSettings(
        RemoteConfigSettings(
          // 앱 시작을 붙잡는 조회다. 길게 주면 스플래시가 그만큼 길어진다.
          fetchTimeout: const Duration(seconds: 10),
          // 개발에서는 캐시를 끈다 — 콘솔에서 값을 고치고 바로 확인해야 한다.
          // (너무 잦으면 서버가 거절한다. 그때는 아래 catch 가 받아서 빈 값으로
          // 끝난다 — 개발에서만 보이는 로그다.)
          // 운영은 한 시간. 켤 때마다 묻는 값이 아니다.
          minimumFetchInterval: isDevFlavor
              ? Duration.zero
              : const Duration(hours: 1),
        ),
      );

      // 네트워크가 없으면 던진다 — 아래 catch 가 받아서 빈 값으로 끝낸다.
      // 캐시된 값이 있으면 그걸로 활성화된다.
      await remote.fetchAndActivate();

      final values = RemoteValues(
        latest: remote.getString(RemoteKeys.latest),
        minimum: remote.getString(RemoteKeys.minimum),
        message: remote.getString(RemoteKeys.message),
        urlIos: remote.getString(RemoteKeys.urlIos),
        urlAndroid: remote.getString(RemoteKeys.urlAndroid),
        slackUserIds: remote.getString(RemoteKeys.slackUserIds),
      );
      // **받아온 것을 남긴다.** 콘솔 값을 고치고 확인할 때 볼 곳이 여기다.
      // 멘션 매핑은 사내 전원의 이메일·Slack ID 라 **명단을 찍지 않고 수만**
      // 적는다 — 로그는 기기에 남고 붙여넣어 공유되기도 한다.
      log.i(
        '원격 설정: 최신 "${values.latest}" · 최소 "${values.minimum}" · '
        '받는 곳 "${values.updateUrl}" · '
        'Slack 매핑 ${_countPairs(values.slackUserIds)}명',
      );
      return values;
    } on Object catch (e, st) {
      log.w('원격 설정을 받지 못했습니다.', error: e, stackTrace: st);
      return RemoteValues.empty;
    }
  }

  /// 로그용 개수. 형식이 깨진 조각은 세지 않는다 —
  /// `SlackRepository.parseUserIds` 가 버리는 것과 같은 기준이어야 한다.
  static int _countPairs(String raw) {
    if (raw.trim().isEmpty) return 0;
    return raw.split(',').where((p) => p.indexOf(':') > 0).length;
  }

  /// `.env` 의 값으로 `FirebaseOptions` 를 조립한다. 하나라도 비면 null.
  ///
  /// 반쯤 채워진 설정으로 초기화하면 Firebase 가 뒤늦게 알 수 없는 오류를
  /// 던진다 — 비었으면 아예 시작하지 않고 로그로 말하는 쪽이 낫다.
  static FirebaseOptions? _options() {
    final projectId = Config.firebaseProjectId;
    final sender = Config.firebaseProjectNumber;
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;
    final apiKey = isIos
        ? Config.firebaseApiKeyIos
        : Config.firebaseApiKeyAndroid;
    final appId = isIos ? Config.firebaseAppIdIos : Config.firebaseAppIdAndroid;

    if (projectId.isEmpty ||
        sender.isEmpty ||
        apiKey.isEmpty ||
        appId.isEmpty) {
      return null;
    }
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: sender,
      projectId: projectId,
    );
  }
}
