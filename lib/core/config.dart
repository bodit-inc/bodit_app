/// 외부 자원 ID 와 자격증명.
///
/// ## 여기 들어가는 값은 보안이 아니다
///
/// `envied` 는 상수를 난독화해서 apk 를 unzip 하고 `strings` 를 돌려도 안 나오게
/// 할 뿐이다. **런타임에는 평문으로 헤더에 실려 나가므로 프록시로 잡힌다.**
/// ADR 에서 이미 알고 감수한 사항이고(전 직원 배포 = APK 추출 가능),
/// 실질 방어선은 다음 둘이다:
///
///   - Anthropic: **콘솔 지출 한도**
///   - Slack: scope 를 `chat:write` · `files:write` 로만 좁히기
///
/// ## 빌드 방법
///
/// 프로젝트 루트에 `.env` 를 만들고(`.gitignore` 에 이미 있다) 아래를 채운 뒤
/// `fvm dart run build_runner build` 를 돌리면 `config.g.dart` 가 생긴다.
///
/// ```text
/// ANTHROPIC_API_KEY=sk-ant-...
/// SLACK_BOT_TOKEN=xoxb-...
/// SLACK_CHANNEL_ID=C...
/// SPREADSHEET_ID=1...
/// DRIVE_FOLDER_ID=1...
/// GOOGLE_IOS_CLIENT_ID=....apps.googleusercontent.com
/// GOOGLE_SERVER_CLIENT_ID=....apps.googleusercontent.com
/// ```
library;

import 'package:envied/envied.dart';

part 'config.g.dart';

@Envied(path: '.env', obfuscate: true)
abstract class Config {
  /// OCR 전용. 다른 용도는 없다.
  @EnviedField(varName: 'ANTHROPIC_API_KEY')
  static final String anthropicApiKey = _Config.anthropicApiKey;

  /// scope 는 `chat:write` · `files:write` 만. 넓히지 않는다.
  @EnviedField(varName: 'SLACK_BOT_TOKEN')
  static final String slackBotToken = _Config.slackBotToken;

  @EnviedField(varName: 'SLACK_CHANNEL_ID')
  static final String slackChannelId = _Config.slackChannelId;

  /// 매입내역 스프레드시트.
  @EnviedField(varName: 'SPREADSHEET_ID')
  static final String spreadsheetId = _Config.spreadsheetId;

  /// 증빙을 모아두는 공유 드라이브 폴더.
  /// `drive.file` scope 로는 폴더를 검색할 수 없어서 ID 를 박아둔다.
  @EnviedField(varName: 'DRIVE_FOLDER_ID')
  static final String driveFolderId = _Config.driveFolderId;

  @EnviedField(varName: 'GOOGLE_IOS_CLIENT_ID', defaultValue: '')
  static final String googleIosClientId = _Config.googleIosClientId;

  @EnviedField(varName: 'GOOGLE_SERVER_CLIENT_ID', defaultValue: '')
  static final String googleServerClientId = _Config.googleServerClientId;
}
