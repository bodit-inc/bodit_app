/// 운영 환경 설정값. `.env.prod` 에서 굽는다.
///
/// **여기에 주석을 길게 달지 않는다** — 각 값이 무엇이고 왜 그런지는
/// `core/config.dart` 가 설명한다. 이 파일은 `.env.prod` 와 1:1 로 대응하는
/// 껍데기일 뿐이고, 개발(`env_dev.dart`)과 **필드가 완전히 같아야 한다**
/// (`test/flavor_config_test.dart` 가 두 `.env.*.example` 의 키를 맞춘다).
library;

import 'package:envied/envied.dart';

part 'env_prod.g.dart';

@Envied(path: '.env.prod', name: 'EnvProd', obfuscate: true)
abstract class EnvProd {
  @EnviedField(varName: 'ANTHROPIC_API_KEY')
  static final String anthropicApiKey = _EnvProd.anthropicApiKey;

  @EnviedField(varName: 'SLACK_BOT_TOKEN')
  static final String slackBotToken = _EnvProd.slackBotToken;

  @EnviedField(varName: 'SLACK_CHANNEL_ID')
  static final String slackChannelId = _EnvProd.slackChannelId;

  @EnviedField(varName: 'SLACK_USER_IDS', defaultValue: '')
  static final String slackUserIds = _EnvProd.slackUserIds;

  @EnviedField(varName: 'SPREADSHEET_ID')
  static final String spreadsheetId = _EnvProd.spreadsheetId;

  @EnviedField(varName: 'CARD_SHEET_ID')
  static final String cardSheetId = _EnvProd.cardSheetId;

  @EnviedField(varName: 'DRIVE_FOLDER_ID')
  static final String driveFolderId = _EnvProd.driveFolderId;

  @EnviedField(varName: 'GOOGLE_IOS_CLIENT_ID', defaultValue: '')
  static final String googleIosClientId = _EnvProd.googleIosClientId;

  @EnviedField(varName: 'GOOGLE_SERVER_CLIENT_ID', defaultValue: '')
  static final String googleServerClientId = _EnvProd.googleServerClientId;
}
