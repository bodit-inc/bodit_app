/// Slack 게시가 돌려주는 **링크**.
///
/// 가장 중요한 계약은 "링크를 못 받아도 게시는 성공이다" 다. 파일은 이미
/// 채널에 올라갔는데 링크 때문에 전송을 실패로 만들면, 재시도에서 **사진이
/// 두 번 올라간다.**
library;

import 'dart:convert';
import 'dart:io';

import 'package:bodit_app/data/remote/slack_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 업로드 3단계 + `files.info` 를 흉내낸다.
///
/// [infoBody] 가 null 이면 `files.info` 가 HTTP 500 을 준다.
MockClient _client({String? infoBody}) {
  return MockClient((req) async {
    final path = req.url.path;
    if (path.endsWith('files.getUploadURLExternal')) {
      return http.Response(
        jsonEncode(<String, Object>{
          'ok': true,
          'upload_url': 'https://files.slack.example/upload',
          'file_id': 'F1',
        }),
        200,
      );
    }
    if (req.url.host == 'files.slack.example') {
      // 2단계는 파일 자체를 그 URL 로 POST 한다. 본문은 안 본다.
      return http.Response('', 200);
    }
    if (path.endsWith('files.completeUploadExternal')) {
      return http.Response(jsonEncode(<String, Object>{'ok': true}), 200);
    }
    if (path.endsWith('files.info')) {
      if (infoBody == null) return http.Response('nope', 500);
      return http.Response(infoBody, 200);
    }
    return http.Response('unexpected ${req.url}', 404);
  });
}

Future<String?> _post(MockClient client, File image) {
  final repo = SlackRepository(
    botToken: 'xoxb-test',
    channelId: 'C123',
    client: client,
  );
  return repo.postEvidence(
    image: image,
    filename: '260805_영풍문고_8월 도서_영수증_19,000',
    belongDate: DateTime(2026, 8, 5),
    vendor: '영풍문고',
    description: '8월 도서',
    totalAmount: 19000,
    currency: 'KRW',
    className: '법인(신용)',
    submittedBy: 'james',
  );
}

void main() {
  late File image;

  setUp(() {
    image = File('${Directory.systemTemp.path}/slack_permalink_test.jpg')
      ..writeAsBytesSync(<int>[1, 2, 3]);
  });

  tearDown(() {
    if (image.existsSync()) image.deleteSync();
  });

  test('files.info 가 permalink 를 주면 그걸 돌려준다', () async {
    final url = await _post(
      _client(
        infoBody: jsonEncode(<String, Object>{
          'ok': true,
          'file': <String, Object>{
            'id': 'F1',
            'permalink': 'https://bodit.slack.com/files/U1/F1/receipt.jpg',
          },
        }),
      ),
      image,
    );
    expect(url, 'https://bodit.slack.com/files/U1/F1/receipt.jpg');
  });

  test('files.info 가 실패해도 던지지 않는다 — 게시는 성공이다', () async {
    // 여기서 던지면 재시도에서 사진이 두 번 올라간다.
    expect(await _post(_client(), image), isNull);
  });

  test('응답에 permalink 가 없어도 던지지 않는다', () async {
    final url = await _post(
      _client(
        infoBody: jsonEncode(<String, Object>{
          'ok': true,
          'file': <String, Object>{'id': 'F1'},
        }),
      ),
      image,
    );
    expect(url, isNull);
  });

  test('게시 자체가 실패하면 던진다', () async {
    // 이쪽은 삼키면 안 된다 — 안 올라간 건을 올라갔다고 하면 증빙이 사라진다.
    final client = MockClient((req) async {
      if (req.url.path.endsWith('files.getUploadURLExternal')) {
        return http.Response(
          jsonEncode(<String, Object>{'ok': false, 'error': 'invalid_auth'}),
          200,
        );
      }
      return http.Response('', 200);
    });
    await expectLater(_post(client, image), throwsA(isA<SlackException>()));
  });
}
