import 'package:bodit_app/data/remote/slack_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Slack 메시지 포맷은 **채널에 그대로 보이는 계약**이다.
/// 사람이 스크롤하며 훑는 형태라 바뀌면 바로 티가 난다. 테스트로 고정한다.
void main() {
  final repo = SlackRepository(botToken: 'xoxb-test', channelId: 'C123');

  test('한 줄 요약 + 제출자 멘션. 링크는 없다', () {
    // 증빙은 메시지에 사진으로 붙어 있어 드라이브 링크가 겹쳤고, 시트는
    // 홈 화면에 같은 링크가 있다. 흘러가는 채널에서는 줄이 짧은 쪽이 낫다.
    final msg = repo.buildComment(
      belongDate: DateTime(2026, 9, 10),
      vendor: '드림디포(에이스)',
      description: '뽁뽁이',
      totalAmount: 8000,
      currency: 'KRW',
      className: '법인(이체)',
      submittedBy: '<@U12345>',
    );

    expect(msg, '''
260910 / 드림디포(에이스) / 뽁뽁이 / 8,000원 / 법인(이체)
<@U12345>''');
  });

  test('멘션을 못 만들면 이메일이 그대로 들어간다', () {
    // 제출자 줄이 비면 누가 올렸는지 모른다.
    final msg = repo.buildComment(
      belongDate: DateTime(2026, 9, 10),
      vendor: '업체',
      description: '내역',
      totalAmount: 1000,
      currency: 'KRW',
      className: '법인(이체)',
      submittedBy: 'james@bodit.co',
    );
    expect(msg.split('\n').last, 'james@bodit.co');
  });

  test('금액에 천 단위 쉼표가 붙는다', () {
    final msg = repo.buildComment(
      belongDate: DateTime(2026, 1, 5),
      vendor: '업체',
      description: '내역',
      totalAmount: 1234567,
      currency: 'KRW',
      className: '법인(신용)',
      submittedBy: 'a@bodit.co',
    );
    expect(msg.split('\n').first, '260105 / 업체 / 내역 / 1,234,567원 / 법인(신용)');
  });

  test('세 자리 이하는 쉼표가 없다', () {
    final msg = repo.buildComment(
      belongDate: DateTime(2026, 12, 31),
      vendor: '업체',
      description: '내역',
      totalAmount: 900,
      currency: 'KRW',
      className: '법인(체크)',
      submittedBy: 'a@bodit.co',
    );
    expect(msg.split('\n').first, '261231 / 업체 / 내역 / 900원 / 법인(체크)');
  });

  test('외화는 코드가 뒤에 붙는다 — 원화로 읽히면 안 된다', () {
    final msg = repo.buildComment(
      belongDate: DateTime(2026, 3, 2),
      vendor: 'Apple Store',
      description: '어댑터',
      totalAmount: 1299, // 센트 단위로 들고 있다
      currency: 'USD',
      className: '법인(신용)',
      submittedBy: 'a@bodit.co',
    );
    expect(
      msg.split('\n').first,
      '260302 / Apple Store / 어댑터 / 12.99 USD / 법인(신용)',
    );
  });
}
