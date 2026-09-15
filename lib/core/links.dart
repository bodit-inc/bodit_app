/// 외부 원본으로 가는 링크.
///
/// **한 곳에 모아둔다.** 같은 URL 을 홈 바로가기와 Slack 메시지가 같이 쓰는데,
/// 각자 문자열을 조립하면 한쪽만 고치게 된다 — 이 프로젝트에서 이미 두 번 겪었다.
///
/// 조회는 앱에서 다시 만들지 않고 원본으로 연결한다(ADR). 그래서 이 링크들이
/// 곧 "조회 기능" 이다.
library;

/// 매입내역 스프레드시트.
String spreadsheetUrl(String spreadsheetId) =>
    'https://docs.google.com/spreadsheets/d/$spreadsheetId/edit';

/// 증빙 폴더.
String driveFolderUrl(String folderId) =>
    'https://drive.google.com/drive/folders/$folderId';

/// Slack 채널.
///
/// `app_redirect` 를 쓰는 이유: 워크스페이스 도메인(`bodit.slack.com`)을 몰라도
/// 되고, Slack 앱이 깔려 있으면 앱으로, 없으면 웹으로 알아서 넘어간다.
/// `slack://` 스킴은 team id 가 따로 필요해서 설정값이 하나 더 늘어난다.
String slackChannelUrl(String channelId) =>
    'https://slack.com/app_redirect?channel=$channelId';
