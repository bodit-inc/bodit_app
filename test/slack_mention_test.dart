/// 제출자를 **멘션**으로 적는다.
///
/// 멘션이면 그 사람에게 알림이 가고 채널에서 눌러 프로필로 갈 수 있다.
/// 이메일 글자만 적혀 있을 때는 둘 다 안 된다.
///
/// ## 왜 `users.lookupByEmail` 이 아닌가
///
/// 그 API 는 **Slack 계정에 적힌 이메일**로만 찾는다. 회사 이메일과 다른
/// 사람이 실제로 있다 — 개인 Gmail 로 가입한 경우다. 조회로는 영원히 못 찾고
/// 이메일 글자로 떨어진다. 사내 매핑은 사람이 연결해둔 것이라 그 경우를 덮는다.
library;

import 'package:bodit_app/data/remote/slack_repository.dart';
import 'package:flutter_test/flutter_test.dart';

SlackRepository repoWith(String userIds, {String remote = ''}) =>
    SlackRepository(
      botToken: 'xoxb-test',
      channelId: 'C123',
      userIds: userIds,
      remoteUserIds: remote,
    );

void main() {
  group('매핑 읽기', () {
    test('email:ID 를 쉼표로 이은 것을 읽는다', () {
      final m = SlackRepository.parseUserIds(
        'a@example.com:U0AAA,b@example.com:U0BBB',
      );
      expect(m, <String, String>{
        'a@example.com': 'U0AAA',
        'b@example.com': 'U0BBB',
      });
    });

    test('공백을 떼고 이메일은 소문자로 맞춘다', () {
      // 매핑 쪽 표기가 어떻든 찾아야 한다.
      final m = SlackRepository.parseUserIds(
        ' A@Example.com : U0AAA , b@example.com:U0BBB ',
      );
      expect(m['a@example.com'], 'U0AAA');
      expect(m['b@example.com'], 'U0BBB');
    });

    test('깨진 조각은 건너뛰고 나머지는 산다', () {
      // 한 사람의 표기가 틀렸다고 나머지 멘션까지 죽을 이유가 없다.
      final m = SlackRepository.parseUserIds(
        'a@example.com:U0AAA,쓰레기,:U0CCC,d@example.com:,,e@example.com:U0EEE',
      );
      expect(m.keys, <String>['a@example.com', 'e@example.com']);
    });

    test('비어 있으면 빈 맵이다', () {
      expect(SlackRepository.parseUserIds(''), isEmpty);
      expect(SlackRepository.parseUserIds('   '), isEmpty);
    });
  });

  group('멘션 만들기', () {
    final repo = repoWith(
      'hong@example.com:U0HONG,gildong@example.com:U0GILDONG',
    );

    test('매핑에 있으면 멘션으로 적는다', () {
      expect(repo.mentionFor('hong@example.com'), '<@U0HONG>');
    });

    test('Slack 계정 이메일이 회사 것과 달라도 찾는다', () {
      // Slack 계정을 개인 메일로 만든 사람은 회사 이메일로 조회가 안 된다.
      // 매핑으로만 덮을 수 있는 경우다. (실제 사내에 이런 계정이 있다.)
      expect(repo.mentionFor('gildong@example.com'), '<@U0GILDONG>');
    });

    test('매핑에 없으면 이메일을 그대로 적는다', () {
      // Slack 계정이 아예 없는 사람이 있고, 입사자가 매핑에 추가되기 전일
      // 수도 있다. 제출자 줄이 비면 누가 올렸는지 모른다.
      expect(repo.mentionFor('nobody@example.com'), 'nobody@example.com');
    });

    test('대소문자와 앞뒤 공백을 가리지 않는다', () {
      expect(repo.mentionFor(' Hong@Example.COM '), '<@U0HONG>');
    });

    test('빈 이메일은 그대로 둔다', () {
      expect(repo.mentionFor(''), '');
    });

    test('매핑이 비어 있으면 전부 이메일로 떨어진다', () {
      // 설정을 안 넣었거나 build_runner 를 안 돌린 상태다. 터지지는 않는다.
      expect(repoWith('').mentionFor('hong@example.com'), 'hong@example.com');
    });
  });

  /// 명단이 두 겹이다 — `.env` 에 구워진 바닥 위에 Remote Config 가 얹힌다.
  /// 입사자를 콘솔에 한 줄 적으면 **재배포 없이** 멘션이 붙는 것이 요점이다.
  group('원격 매핑이 구워진 매핑을 덮는다', () {
    const baked = 'hong@example.com:U0HONG';

    test('원격에만 있는 사람도 멘션된다 — 입사자를 재배포 없이 추가한다', () {
      final repo = repoWith(baked, remote: 'new@example.com:U0NEW');
      expect(repo.mentionFor('new@example.com'), '<@U0NEW>');
    });

    test('구워진 명단은 그대로 산다 — 원격에 한 사람만 적어도 나머지가 안 죽는다', () {
      // 콘솔에 전체 명단을 다시 쓰게 만들면 아무도 그렇게 하지 않는다.
      final repo = repoWith(baked, remote: 'new@example.com:U0NEW');
      expect(repo.mentionFor('hong@example.com'), '<@U0HONG>');
    });

    test('같은 이메일이 양쪽에 있으면 원격이 이긴다', () {
      // Slack 계정을 새로 만든 사람의 id 를 고치는 길이다.
      final repo = repoWith(baked, remote: 'hong@example.com:U0NEWID');
      expect(repo.mentionFor('hong@example.com'), '<@U0NEWID>');
    });

    test('원격이 비어 있으면 구워진 명단만 쓴다 — 조회 전·실패·Firebase 미설정', () {
      // `RemoteValues.empty` 가 들어오는 세 경우가 전부 여기로 떨어진다.
      final repo = repoWith(baked);
      expect(repo.mentionFor('hong@example.com'), '<@U0HONG>');
    });

    test('원격 값이 깨져도 구워진 명단은 살아남는다', () {
      // 콘솔에 오타가 하나 들어갔다고 전원의 멘션이 사라지면 안 된다.
      final repo = repoWith(baked, remote: '쓰레기,,:U0X');
      expect(repo.mentionFor('hong@example.com'), '<@U0HONG>');
    });
  });
}
