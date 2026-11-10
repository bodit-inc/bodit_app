/// "지금 쓰는 버전이 낡았나" 의 답.
///
/// Remote Config 에서 읽은 값과 지금 버전을 **이미 비교해둔 결과**다.
/// 화면은 다시 비교하지 않는다 — 비교 규칙이 두 군데로 갈리면 배너와 차단
/// 화면이 서로 다른 말을 한다.
library;

import 'package:bodit_app/core/version.dart';

/// 얼마나 급한가. 화면이 이것만 보고 갈린다.
enum UpdateUrgency {
  /// 최신이거나, 비교할 수 없었다(원격 값이 없음·파싱 실패·조회 실패).
  /// **아무것도 띄우지 않는다.**
  none,

  /// 새 버전이 있다. 안내만 하고 쓰는 것은 막지 않는다.
  optional,

  /// 최소 버전에 못 미친다. **홈에 들어가지 못한다.**
  ///
  /// 이 단계가 있는 이유: 시트는 append-only 라 잘못 쓰는 버전이 돌아다니면
  /// 들어간 행을 앱으로 되돌릴 수 없다. 그럴 때 전원을 즉시 세울 길이
  /// 하나는 있어야 한다.
  blocked,
}

/// 업데이트 안내에 필요한 것 전부.
class AppUpdate {
  const AppUpdate({
    required this.urgency,
    this.current,
    this.latest,
    this.message,
    this.url,
  });

  /// 비교할 수 없었거나 최신일 때. 화면은 아무것도 그리지 않는다.
  static const none = AppUpdate(urgency: UpdateUrgency.none);

  final UpdateUrgency urgency;

  /// 지금 깔려 있는 버전. 안내 문구에 같이 적는다 — "몇에서 몇으로" 가
  /// 없으면 사용자가 이미 업데이트했는지 알 수 없다.
  final AppVersion? current;

  /// 원격이 말한 최신 버전.
  final AppVersion? latest;

  /// 콘솔에서 적어 보내는 한 줄. 비어 있을 수 있다.
  ///
  /// **무엇이 바뀌었는지**를 적는 자리다. 앱을 다시 빌드하지 않고 문구만
  /// 고칠 수 있어야 해서 원격 값으로 뒀다.
  final String? message;

  /// 받으러 갈 곳. iOS 는 TestFlight, Android 는 App Distribution 링크다.
  ///
  /// **원격 값이다.** 테스터 그룹을 새로 만들면 링크가 바뀌는데, 그걸
  /// 앱에 박아두면 링크를 고치려고 업데이트를 받아야 한다 — 업데이트를
  /// 못 받는 사람에게 업데이트를 받으라고 하는 꼴이 된다.
  /// 비어 있으면 화면이 버튼을 감추고 "스토어에서 받으세요" 로 끝낸다.
  final String? url;
}
