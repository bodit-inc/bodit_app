/// "새 버전이 올라왔나" 를 Firebase Remote Config 에 묻는다.
///
/// ## 왜 Remote Config 인가
///
/// 배포가 TestFlight(iOS)·Firebase App Distribution(Android)으로 나간다.
/// 둘 다 **올린 쪽은 알지만 깔린 쪽은 모른다** — 설치된 앱에 "새 빌드가
/// 있다" 고 말해주는 길이 없다(TestFlight 알림은 앱을 받은 사람 중 알림을
/// 켜둔 사람에게만 간다). 그래서 앱이 켜질 때 스스로 물어본다.
///
/// 올린 뒤 콘솔에서 `latest_version` 한 줄을 고치면 전원에게 전달된다 —
/// 그 한 줄을 고치려고 앱을 다시 빌드할 일이 없어야 하므로 설정이 아니라
/// **원격 값**이다.
///
/// ## Firebase 를 여기서만 쓴다
///
/// 이 앱의 Firebase 용도는 이것 하나다. 그래서 `Firebase.initializeApp` 도
/// 여기서 부른다 — Analytics·Crashlytics·푸시가 붙으면 그때 앱 시작으로
/// 올리고 `FirebaseOptions` 조립도 밖으로 뺀다. 지금 미리 나누면 쓰지도
/// 않는 층이 하나 생긴다.
///
/// ## 실패하면 조용히 포기한다 (던지지 않는다)
///
/// 비행기 모드·Firebase 설정 미입력·원격 값 오타 — 전부 "안내를 못 한다" 로
/// 끝나야 한다. 업데이트 안내는 **보여주는 기능**이고, 못 물어봤다고 앱을
/// 못 쓰게 만들 이유가 없다(`AppInfo.load()` 와 같은 규칙). 로그에는 남긴다.
///
/// 단 **`minimum_version` 에 걸리면 막는다.** 그건 "못 물어봤다" 가 아니라
/// "물어봤고 쓰면 안 된다는 답을 받았다" 다 — 시트가 append-only 라
/// 잘못 쓰는 버전이 돌아다니는 쪽이 더 비싸다.
library;

import 'package:bodit_app/core/app_info.dart';
import 'package:bodit_app/core/config.dart';
import 'package:bodit_app/core/flavor.dart';
import 'package:bodit_app/core/log.dart';
import 'package:bodit_app/core/version.dart';
import 'package:bodit_app/models/app_update.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

/// Remote Config 파라미터 이름. **콘솔에 적은 글자와 한 글자도 달라선 안 된다** —
/// 틀리면 기본값(빈 문자열)이 나오고, 그건 "새 버전 없음" 과 구분되지 않는다.
abstract final class UpdateKeys {
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
}

class AppUpdateService {
  const AppUpdateService();

  /// 지금 버전이 낡았는지 묻는다. **던지지 않는다** — 모르면 [AppUpdate.none].
  Future<AppUpdate> check() async {
    final current = AppInfo.current;
    if (current == null) {
      // `AppInfo.load()` 가 실패했거나 아직 안 불렸다. 지금 버전을 모르는데
      // 낡았다고 말할 수는 없다 — 특히 막을 수는 없다.
      log.w('지금 버전을 몰라 업데이트 확인을 건너뜁니다.');
      return AppUpdate.none;
    }

    final options = _options();
    if (options == null) {
      log.i('Firebase 설정이 비어 있어 업데이트 확인을 건너뜁니다. (.env 의 FIREBASE_*)');
      return AppUpdate.none;
    }

    try {
      // hot restart 하면 이미 초기화돼 있다. 또 부르면 duplicate-app 으로 던진다.
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: options);
      }
      final remote = FirebaseRemoteConfig.instance;

      // 기본값을 먼저 깐다. **전부 빈 문자열 = 안내도 차단도 없음** —
      // 조회가 늦거나 실패했을 때 나오는 값이 "아무 일 없음" 이어야 한다.
      await remote.setDefaults(const {
        UpdateKeys.latest: '',
        UpdateKeys.minimum: '',
        UpdateKeys.message: '',
        UpdateKeys.urlIos: '',
        UpdateKeys.urlAndroid: '',
      });

      await remote.setConfigSettings(
        RemoteConfigSettings(
          // 앱 시작을 붙잡는 조회다. 길게 주면 스플래시가 그만큼 길어진다.
          fetchTimeout: const Duration(seconds: 10),
          // 개발에서는 캐시를 끈다 — 콘솔에서 값을 고치고 바로 확인해야 한다.
          // (너무 잦으면 서버가 거절한다. 그때는 아래 catch 가 받아서 안내가
          // 안 뜨고 끝난다 — 개발에서만 보이는 로그다.)
          // 운영은 한 시간. 켤 때마다 묻는 값이 아니다.
          minimumFetchInterval: isDevFlavor
              ? Duration.zero
              : const Duration(hours: 1),
        ),
      );

      // 네트워크가 없으면 던진다 — 아래 catch 가 받아서 "모름" 으로 끝낸다.
      // 캐시된 값이 있으면 그걸로 활성화된다.
      await remote.fetchAndActivate();

      final latest = remote.getString(UpdateKeys.latest);
      final minimum = remote.getString(UpdateKeys.minimum);
      // **판정 전에 꺼내 둔다.** 최신일 때는 `AppUpdate.none` 이라 결과에
      // 링크가 안 실리는데, 로그에는 "콘솔에 뭐가 적혀 있었는지" 가 남아야
      // 한다 — 안 그러면 링크를 넣었는지조차 로그로 확인할 수 없다.
      final url = switch (defaultTargetPlatform) {
        TargetPlatform.iOS => remote.getString(UpdateKeys.urlIos),
        _ => remote.getString(UpdateKeys.urlAndroid),
      };
      final result = _read(
        current: current,
        latest: latest,
        minimum: minimum,
        message: remote.getString(UpdateKeys.message),
        url: url,
      );
      // **판정을 남긴다.** 안내가 안 떴을 때 "조회가 안 된 것" 과 "조회는
      // 됐는데 최신이라 안 뜬 것" 은 화면에서 구분되지 않는다. 콘솔 값을
      // 고치고 확인할 때 볼 곳이 여기다.
      log.i(
        '업데이트 확인: 지금 $current · 최신 "$latest" · 최소 "$minimum" '
        '→ ${result.urgency.name} · 받는 곳 "$url"',
      );
      return result;
    } on Object catch (e, st) {
      log.w('업데이트 확인에 실패했습니다.', error: e, stackTrace: st);
      return AppUpdate.none;
    }
  }

  /// 읽어온 문자열을 판정으로 바꾼다. **네트워크를 모르는 순수 함수라
  /// 테스트가 이것만 본다.**
  @visibleForTesting
  static AppUpdate read({
    required AppVersion current,
    required String latest,
    required String minimum,
    String message = '',
    String url = '',
  }) => _read(
    current: current,
    latest: latest,
    minimum: minimum,
    message: message,
    url: url,
  );

  static AppUpdate _read({
    required AppVersion current,
    required String latest,
    required String minimum,
    required String message,
    required String url,
  }) {
    // 읽을 수 없는 값은 **없는 것으로 친다.** 콘솔에 오타가 하나 들어갔다고
    // 전원이 막히거나, 반대로 엉뚱한 버전이 최신이 되면 안 된다.
    final newest = AppVersion.tryParse(latest);
    final floor = AppVersion.tryParse(minimum);
    if (latest.trim().isNotEmpty && newest == null) {
      log.w('$latest 를 버전으로 읽지 못했습니다 (${UpdateKeys.latest}).');
    }
    if (minimum.trim().isNotEmpty && floor == null) {
      log.w('$minimum 를 버전으로 읽지 못했습니다 (${UpdateKeys.minimum}).');
    }

    final UpdateUrgency urgency;
    if (floor != null && current.isOlderThan(floor)) {
      // 차단이 먼저다 — 둘 다 걸리면 막는 쪽이 이긴다.
      urgency = UpdateUrgency.blocked;
    } else if (newest != null && current.isOlderThan(newest)) {
      urgency = UpdateUrgency.optional;
    } else {
      return AppUpdate.none;
    }

    return AppUpdate(
      urgency: urgency,
      current: current,
      // 차단인데 `latest_version` 이 비어 있을 수 있다. 그때는 최소 버전이
      // 곧 받아야 할 버전이다 — 화면에 적을 숫자가 있어야 한다.
      latest: newest ?? floor,
      message: message.trim().isEmpty ? null : message.trim(),
      url: url.trim().isEmpty ? null : url.trim(),
    );
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
