/// 개발 환경 설정값. `.env.dev` 에서 굽는다.
///
/// **여기에 주석을 길게 달지 않는다** — 각 값이 무엇이고 왜 그런지는
/// `core/config.dart` 가 설명한다. 이 파일은 `.env.dev` 와 1:1 로 대응하는
/// 껍데기일 뿐이고, 운영(`env_prod.dart`)과 **필드가 완전히 같아야 한다**
/// (`test/flavor_config_test.dart` 가 두 `.env.*.example` 의 키를 맞춘다).
library;

import 'package:envied/envied.dart';

part 'env_dev.g.dart';

@Envied(path: '.env.dev', name: 'EnvDev', obfuscate: true)
abstract class EnvDev {
  @EnviedField(varName: 'ANTHROPIC_API_KEY')
  static final String anthropicApiKey = _EnvDev.anthropicApiKey;

  @EnviedField(varName: 'SLACK_BOT_TOKEN')
  static final String slackBotToken = _EnvDev.slackBotToken;

  @EnviedField(varName: 'SLACK_CHANNEL_ID')
  static final String slackChannelId = _EnvDev.slackChannelId;

  @EnviedField(varName: 'SLACK_USER_IDS', defaultValue: '')
  static final String slackUserIds = _EnvDev.slackUserIds;

  @EnviedField(varName: 'SPREADSHEET_ID')
  static final String spreadsheetId = _EnvDev.spreadsheetId;

  @EnviedField(varName: 'CARD_SHEET_ID')
  static final String cardSheetId = _EnvDev.cardSheetId;

  @EnviedField(varName: 'DRIVE_FOLDER_ID')
  static final String driveFolderId = _EnvDev.driveFolderId;

  @EnviedField(varName: 'GOOGLE_IOS_CLIENT_ID', defaultValue: '')
  static final String googleIosClientId = _EnvDev.googleIosClientId;

  @EnviedField(varName: 'GOOGLE_SERVER_CLIENT_ID', defaultValue: '')
  static final String googleServerClientId = _EnvDev.googleServerClientId;
}
