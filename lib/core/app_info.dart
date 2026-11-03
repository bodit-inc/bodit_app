/// 앱 자신에 대한 정보. 지금은 버전 하나다.
///
/// ## 버전의 원천은 `pubspec.yaml` 이다
///
/// `version: 1.0.0+2` 한 줄이 원천이고, 거기서 **네이티브를 거쳐** 돌아온다 —
/// `flutter build` 가 그 값을 안드로이드 `versionName`(`android/app/build.gradle.kts`
/// 의 `flutter.versionName`)과 iOS `CFBundleShortVersionString`
/// (`$(FLUTTER_BUILD_NAME)`)으로 내려보내고, `package_info_plus` 가 그걸 읽는다.
///
/// 돌아가는 길처럼 보이지만 다른 두 방법이 더 나쁘다:
///
///   - `--dart-define` 으로 넘기기 — `Makefile` 을 안 거치는 빌드 경로에서
///     빈 값이 된다. 운영은 `--flavor` 없이 Xcode `Runner` 스킴으로도 돌아야
///     하므로(CLAUDE.md "환경 분리" 1) 플래그에 의존할 수 없다
///   - 상수로 적어두기 — `pubspec.yaml` 의 버전을 올릴 때 한쪽만 낡는다.
///     개발 아이콘을 손으로 만들지 않는 것과 같은 이유다
///
/// ## 왜 static 인가
///
/// 화면이 버전을 비동기로 기다릴 이유가 없다. `main()` 이 `runApp` 전에 한 번
/// 읽어두면 호출부는 `AppInfo.version` 만 본다 — `Config` 와 같은 모양이다.
library;

import 'package:bodit_app/core/log.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 앱 버전. [load] 로 채운다.
abstract final class AppInfo {
  static String _version = '';

  /// `1.0.0 (2)` 꼴. **못 읽었으면 빈 문자열이다** — [load] 전이거나 플랫폼
  /// 조회가 실패한 경우다. 부르는 쪽이 비었으면 그 줄을 감춘다.
  static String get version => _version;

  /// `main()` 이 `runApp` 전에 한 번 부른다.
  ///
  /// **실패해도 던지지 않는다.** 환경 설정(`Config.ensureConfigured`)은 틀리면
  /// 운영 시트를 더럽히니 앱을 세우는 게 맞지만, 버전은 보여주는 값일 뿐이라
  /// 못 읽었다고 앱을 못 쓰게 만들 이유가 없다. 대신 로그에는 남긴다.
  static Future<void> load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _version = info.buildNumber.isEmpty
          ? info.version
          : '${info.version} (${info.buildNumber})';
    } on Object catch (e, st) {
      log.w('앱 버전을 읽지 못했습니다.', error: e, stackTrace: st);
    }
  }
}
