/// "새 버전이 올라왔나" 를 판정한다. 원격 값은 [RemoteConfigService] 가 받아온다.
///
/// ## 왜 원격 값인가
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
/// ## Firebase 조회는 여기 없다
///
/// 예전에는 이 파일이 `Firebase.initializeApp` 부터 다 했다. 용도가 하나일
/// 때는 그게 맞았지만 **두 번째 소비자**(Slack 멘션 매핑)가 붙어서
/// `remote_config.dart` 로 뺐다. 조회가 둘이면 운영의 캐시 간격(1시간)
/// 때문에 서로 다른 시점의 값을 보게 된다.
///
/// 그래서 이 파일에는 **판정만** 남았다 — 네트워크를 모르는 순수 로직이라
/// 테스트가 이것만 본다.
///
/// ## 모르면 포기한다 (던지지 않는다)
///
/// 조회 실패는 [RemoteValues.empty] 로 들어오고, 그건 "안내도 차단도 없음"
/// 이다. 업데이트 안내는 **보여주는 기능**이고, 못 물어봤다고 앱을 못 쓰게
/// 만들 이유가 없다(`AppInfo.load()` 와 같은 규칙).
///
/// 단 **`minimum_version` 에 걸리면 막는다.** 그건 "못 물어봤다" 가 아니라
/// "물어봤고 쓰면 안 된다는 답을 받았다" 다 — 시트가 append-only 라
/// 잘못 쓰는 버전이 돌아다니는 쪽이 더 비싸다.
library;

import 'package:bodit_app/core/app_info.dart';
import 'package:bodit_app/core/log.dart';
import 'package:bodit_app/core/version.dart';
import 'package:bodit_app/data/remote/remote_config.dart';
import 'package:bodit_app/models/app_update.dart';
import 'package:flutter/foundation.dart';

class AppUpdateService {
  const AppUpdateService();

  /// 받아온 원격 값으로 지금 버전이 낡았는지 본다.
  /// **던지지 않는다** — 모르면 [AppUpdate.none].
  AppUpdate judge(RemoteValues values) {
    final current = AppInfo.current;
    if (current == null) {
      // `AppInfo.load()` 가 실패했거나 아직 안 불렸다. 지금 버전을 모르는데
      // 낡았다고 말할 수는 없다 — 특히 막을 수는 없다.
      log.w('지금 버전을 몰라 업데이트 확인을 건너뜁니다.');
      return AppUpdate.none;
    }

    // **판정 전에 꺼내 둔다.** 최신일 때는 `AppUpdate.none` 이라 결과에
    // 링크가 안 실리는데, 로그에는 "콘솔에 뭐가 적혀 있었는지" 가 남아야
    // 한다 — 안 그러면 링크를 넣었는지조차 로그로 확인할 수 없다.
    final url = values.updateUrl;
    final result = _read(
      current: current,
      latest: values.latest,
      minimum: values.minimum,
      message: values.message,
      url: url,
    );
    // **판정을 남긴다.** 안내가 안 떴을 때 "조회가 안 된 것" 과 "조회는
    // 됐는데 최신이라 안 뜬 것" 은 화면에서 구분되지 않는다.
    log.i(
      '업데이트 확인: 지금 $current · 최신 "${values.latest}" · '
      '최소 "${values.minimum}" → ${result.urgency.name} · 받는 곳 "$url"',
    );
    return result;
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
      log.w('$latest 를 버전으로 읽지 못했습니다 (${RemoteKeys.latest}).');
    }
    if (minimum.trim().isNotEmpty && floor == null) {
      log.w('$minimum 를 버전으로 읽지 못했습니다 (${RemoteKeys.minimum}).');
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
}
