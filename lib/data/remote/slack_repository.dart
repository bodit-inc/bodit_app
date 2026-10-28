/// 매입 내용과 증빙사진을 Slack `#purchase` 에 올린다.
///
/// 지금 사람이 그 채널에 손으로 던지던 일을 앱이 대신한다.
///
/// ## 함정 ② — `files.upload` 은 죽었다 (2025-11-12 sunset)
///
/// 파일 업로드가 **한 번의 호출이 아니라 3단계**다:
///   1. `files.getUploadURLExternal` → 업로드 URL + file id
///   2. 그 URL 로 파일 POST (multipart)
///   3. `files.completeUploadExternal` → 채널에 공유 확정
///
/// 3단계 중간에 실패하면 Slack 에 **고아 파일**이 남는다(어느 채널에도 안 붙은 상태).
/// 재시도하면 파일이 하나 더 생기지만 채널에는 한 번만 뜬다 — 중복 게시보다는 낫다.
///
/// ## 대안이 남아 있다
///
/// Incoming Webhook 으로 텍스트만 보내면 이 3단계가 통째로 사라진다. 다만
/// **제출자 멘션 때문에 Bot 토큰은 여전히 필요하다** — 이메일로 user id 를
/// 찾는 데 `users.lookupByEmail` 을 쓴다. 회계 담당자 답변을 받으면 다시 재본다.
library;

import 'dart:convert';
import 'dart:io';

import 'package:bodit_app/core/utils/currency.dart';
import 'package:bodit_app/core/utils/filename.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class SlackRepository {
  SlackRepository({
    required String botToken,
    required this.channelId,
    http.Client? client,
  }) : _token = botToken,
       _client = client ?? http.Client();

  final String _token;
  final String channelId;
  final http.Client _client;

  /// 이메일 → Slack user id. **앱 세션 동안 들고 있는다.**
  ///
  /// 같은 사람이 계속 올리는데 제출마다 조회할 이유가 없다. provider 가
  /// 싱글톤이라 앱이 떠 있는 동안 유지된다.
  final _userIds = <String, String>{};

  Map<String, String> get _auth => <String, String>{
    'Authorization': 'Bearer $_token',
  };

  /// 증빙사진 + 매입 내용을 채널에 올린다.
  ///
  /// 올라간 파일의 **permalink** 를 돌려준다. 못 받으면 `null` —
  /// 그래도 게시는 성공이다(아래 주석 참조).
  Future<String?> postEvidence({
    required File image,
    required String filename,
    required DateTime belongDate,
    required String vendor,
    required String description,
    required int totalAmount,
    required String currency,
    required String className,
    required String submittedBy,
  }) async {
    final comment = buildComment(
      belongDate: belongDate,
      vendor: vendor,
      description: description,
      totalAmount: totalAmount,
      currency: currency,
      className: className,
      submittedBy: await mentionFor(submittedBy),
    );

    final length = await image.length();

    // ── 1단계: 업로드 URL 받기 ─────────────────────────────────────
    final step1 = await _client.post(
      Uri.parse('https://slack.com/api/files.getUploadURLExternal'),
      headers: <String, String>{
        ..._auth,
        'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
      },
      body: <String, String>{'filename': filename, 'length': '$length'},
    );
    final r1 = _decode(step1, 'files.getUploadURLExternal');
    final uploadUrl = r1['upload_url'] as String;
    final fileId = r1['file_id'] as String;

    // ── 2단계: 파일 자체를 그 URL 로 POST ──────────────────────────
    final req = http.MultipartRequest('POST', Uri.parse(uploadUrl))
      ..files.add(await http.MultipartFile.fromPath('file', image.path));
    final step2 = await http.Response.fromStream(await _client.send(req));
    if (step2.statusCode != 200) {
      throw SlackException('파일 업로드 실패 (${step2.statusCode})');
    }

    // ── 3단계: 채널에 공유 확정 ────────────────────────────────────
    final step3 = await _client.post(
      Uri.parse('https://slack.com/api/files.completeUploadExternal'),
      headers: <String, String>{
        ..._auth,
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: jsonEncode(<String, Object>{
        'files': <Object>[
          <String, String>{'id': fileId, 'title': filename},
        ],
        'channel_id': channelId,
        'initial_comment': comment,
      }),
    );
    _decode(step3, 'files.completeUploadExternal');

    // ── 링크 받기 ─────────────────────────────────────────────────
    //
    // `files.completeUploadExternal` 응답에는 **메시지 ts 가 없다.** 파일
    // permalink 를 열면 Slack 이 그 파일과 붙은 메시지를 같이 보여주므로
    // 그걸로 충분하다 — ts 로 메시지 permalink 를 만들려면 `shares` 를 읽고
    // `chat.getPermalink` 를 또 불러야 해서 호출이 두 번 늘어난다.
    //
    // **여기서 던지지 않는다.** 파일은 이미 채널에 올라갔다. 링크를 못 받은
    // 것 때문에 전송을 실패로 만들면 재시도에서 **사진이 두 번 올라간다.**
    try {
      final info = await _client.post(
        Uri.parse('https://slack.com/api/files.info'),
        headers: <String, String>{
          ..._auth,
          'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
        },
        body: <String, String>{'file': fileId},
      );
      final r = _decode(info, 'files.info');
      final f = r['file'];
      if (f is Map && f['permalink'] is String) return f['permalink'] as String;
    } on Object catch (e) {
      debugPrint('Slack 파일 링크를 받지 못했다 (게시는 성공): $e');
    }
    return null;
  }

  /// 채널에 붙는 메시지.
  ///
  /// 한 줄로 요약하고 제출자를 아래에 둔다 — `#purchase` 는 흘러가는 채널이라
  /// 스크롤하면서 훑을 수 있어야 한다. 사람이 손으로 던지던 시절의 형태에 맞춘다.
  ///
  /// ```text
  /// 260910 / 드림디포(에이스) / 뽁뽁이 / 8,000원 / 법인(이체)
  /// <@U12345>
  /// ```
  ///
  /// ## 링크를 넣지 않는다
  ///
  /// 예전엔 "드라이브에서보기"·"스프레드시트에서보기" 두 줄이 붙었다.
  /// 증빙은 **메시지에 사진으로 붙어 있어** 드라이브 링크가 겹쳤고,
  /// 시트는 홈 화면에 같은 링크가 있다. 흘러가는 채널에서 줄이 짧은 쪽이
  /// 훑기 쉽다.
  @visibleForTesting
  String buildComment({
    required DateTime belongDate,
    required String vendor,
    required String description,
    required int totalAmount,
    required String currency,
    required String className,
    required String submittedBy,
  }) {
    return [
      [
        formatDateForFilename(belongDate),
        vendor,
        description,
        currencyOf(currency).formatWithCode(totalAmount),
        className,
      ].join(' / '),
      submittedBy,
    ].join('\n');
  }

  /// 이메일로 Slack 사용자를 찾아 **멘션 문자열**을 만든다.
  ///
  /// 멘션이면 그 사람에게 알림이 가고 채널에서 눌러 프로필로 갈 수 있다.
  /// 이메일 글자만 적혀 있을 때는 둘 다 안 된다.
  ///
  /// ## 못 찾으면 이메일을 그대로 돌려준다
  ///
  /// Slack 계정이 없을 수도 있고, **Google 로그인 이메일과 Slack 이메일이
  /// 다를 수도 있다**(둘 다 `@bodit.co` 라도 보장은 없다). 그때 제출자 줄이
  /// 비면 누가 올렸는지 모른다.
  ///
  /// ## 실패가 게시를 막지 않는다
  ///
  /// 멘션은 부가 정보다. 이것 때문에 전송을 실패로 만들면 재시도에서
  /// **사진이 두 번 올라간다** — `files.info` 와 같은 이유다.
  @visibleForTesting
  Future<String> mentionFor(String email) async {
    if (email.isEmpty) return email;
    final cached = _userIds[email];
    if (cached != null) return '<@$cached>';
    try {
      final res = await _client.post(
        Uri.parse('https://slack.com/api/users.lookupByEmail'),
        headers: <String, String>{
          ..._auth,
          'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
        },
        body: <String, String>{'email': email},
      );
      final r = _decode(res, 'users.lookupByEmail');
      final user = r['user'];
      if (user is Map && user['id'] is String) {
        final id = user['id'] as String;
        _userIds[email] = id;
        return '<@$id>';
      }
    } on Object catch (e) {
      debugPrint('Slack 사용자를 찾지 못했다 (이메일을 그대로 적는다): $e');
    }
    return email;
  }

  /// Slack 은 실패해도 **HTTP 200** 을 준다. 본문의 `ok` 를 봐야 한다.
  Map<String, dynamic> _decode(http.Response res, String method) {
    if (res.statusCode != 200) {
      throw SlackException('$method HTTP ${res.statusCode}');
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (body['ok'] != true) {
      throw SlackException('$method 실패: ${body['error']}');
    }
    return body;
  }
}

class SlackException implements Exception {
  const SlackException(this.message);

  final String message;

  @override
  String toString() => message;
}
