import 'package:bodit_app/data/remote/slack_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Slack 메시지 포맷은 **채널에 그대로 보이는 계약**이다.
/// 사람이 스크롤하며 훑는 형태라 바뀌면 바로 티가 난다. 테스트로 고정한다.
void main() {
  final repo = SlackRepository(
    botToken: 'xoxb-test',
    channelId: 'C123',
    spreadsheetId: 'SHEET123',
  );

  test('한 줄 요약 + 제출자 + 링크 두 개', () {
    final msg = repo.buildComment(
      belongDate: DateTime(2026, 9, 10),
      vendor: '드림디포(에이스)',
      description: '뽁뽁이',
      totalAmount: 8000,
      className: '법인(이체)',
      submittedBy: 'james@bodit.co',
      driveUrl: 'https://drive.google.com/file/d/ABC/view',
    );

    expect(msg, '''
260910 / 드림디포(에이스) / 뽁뽁이 / 8,000원 / 법인(이체)
james@bodit.co
<https://drive.google.com/file/d/ABC/view|드라이브에서보기>
<https://docs.google.com/spreadsheets/d/SHEET123/edit|스프레드시트에서보기>''');
  });

  test('금액에 천 단위 쉼표가 붙는다', () {
    final msg = repo.buildComment(
      belongDate: DateTime(2026, 1, 5),
      vendor: '업체',
      description: '내역',
      totalAmount: 1234567,
      className: '법인(신용)',
      submittedBy: 'a@bodit.co',
      driveUrl: 'https://x',
    );
    expect(msg.split('\n').first, '260105 / 업체 / 내역 / 1,234,567원 / 법인(신용)');
  });

  test('세 자리 이하는 쉼표가 없다', () {
    final msg = repo.buildComment(
      belongDate: DateTime(2026, 12, 31),
      vendor: '업체',
      description: '내역',
      totalAmount: 900,
      className: '법인(체크)',
      submittedBy: 'a@bodit.co',
      driveUrl: 'https://x',
    );
    expect(msg.split('\n').first, '261231 / 업체 / 내역 / 900원 / 법인(체크)');
  });
}
