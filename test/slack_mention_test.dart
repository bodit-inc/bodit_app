/// 이메일로 Slack 사용자를 찾아 **멘션**으로 적는다.
///
/// 멘션이면 그 사람에게 알림이 가고 채널에서 눌러 프로필로 갈 수 있다.
/// 이메일 글자만 적혀 있을 때는 둘 다 안 된다.
///
/// 못 찾는 경우가 실제로 생긴다 — Slack 계정이 없거나, **Google 로그인
/// 이메일과 Slack 이메일이 다를** 수 있다. 그때 제출자 줄이 비면 누가
/// 올렸는지 모르므로 이메일을 그대로 적는다.
library;

import 'dart:convert';

import 'package:bodit_app/data/remote/slack_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('찾으면 멘션으로 적는다', () async {
    final repo = SlackRepository(
      botToken: 'xoxb-test',
      channelId: 'C123',
      client: MockClient((_) async {
        return http.Response(
          jsonEncode(<String, Object>{
            'ok': true,
            'user': <String, Object>{'id': 'U12345'},
          }),
          200,
        );
      }),
    );
    expect(await repo.mentionFor('james@bodit.co'), '<@U12345>');
  });

  test('못 찾으면 이메일을 그대로 적는다', () async {
    final repo = SlackRepository(
      botToken: 'xoxb-test',
      channelId: 'C123',
      client: MockClient((_) async {
        return http.Response(
          jsonEncode(<String, Object>{'ok': false, 'error': 'users_not_found'}),
          200,
        );
      }),
    );
    expect(await repo.mentionFor('ghost@bodit.co'), 'ghost@bodit.co');
  });

  test('조회가 깨져도 던지지 않는다', () async {
    // 멘션은 부가 정보다. 여기서 던지면 전송이 실패하고, 재시도에서
    // 사진이 두 번 올라간다.
    final repo = SlackRepository(
      botToken: 'xoxb-test',
      channelId: 'C123',
      client: MockClient((_) async => http.Response('nope', 500)),
    );
    expect(await repo.mentionFor('james@bodit.co'), 'james@bodit.co');
  });

  test('한 번 찾으면 다시 묻지 않는다', () async {
    // 같은 사람이 계속 올린다. 제출마다 조회할 이유가 없다.
    var calls = 0;
    final repo = SlackRepository(
      botToken: 'xoxb-test',
      channelId: 'C123',
      client: MockClient((_) async {
        calls++;
        return http.Response(
          jsonEncode(<String, Object>{
            'ok': true,
            'user': <String, Object>{'id': 'U12345'},
          }),
          200,
        );
      }),
    );
    expect(await repo.mentionFor('james@bodit.co'), '<@U12345>');
    expect(await repo.mentionFor('james@bodit.co'), '<@U12345>');
    expect(calls, 1);
  });

  test('못 찾은 것은 캐시하지 않는다', () async {
    // 나중에 Slack 계정이 생길 수 있다. 영구히 이메일만 적으면 그걸 못 받는다.
    var calls = 0;
    final repo = SlackRepository(
      botToken: 'xoxb-test',
      channelId: 'C123',
      client: MockClient((_) async {
        calls++;
        return http.Response(
          jsonEncode(<String, Object>{'ok': false, 'error': 'users_not_found'}),
          200,
        );
      }),
    );
    await repo.mentionFor('ghost@bodit.co');
    await repo.mentionFor('ghost@bodit.co');
    expect(calls, 2);
  });

  test('빈 이메일은 묻지 않는다', () async {
    var calls = 0;
    final repo = SlackRepository(
      botToken: 'xoxb-test',
      channelId: 'C123',
      client: MockClient((_) async {
        calls++;
        return http.Response('', 200);
      }),
    );
    expect(await repo.mentionFor(''), '');
    expect(calls, 0);
  });
}
