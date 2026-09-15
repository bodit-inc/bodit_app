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
/// Incoming Webhook 으로 **텍스트 + Drive 링크**만 보내면 이 3단계가 통째로 사라지고
/// Bot 토큰도 필요 없다. 회계 담당자 답변을 받으면 다시 재본다.
library;

import 'dart:convert';
import 'dart:io';

import 'package:bodit_app/core/links.dart';
import 'package:bodit_app/core/utils/currency.dart';
import 'package:bodit_app/core/utils/filename.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class SlackRepository {
  SlackRepository({
    required String botToken,
    required this.channelId,
    required this.spreadsheetId,
    http.Client? client,
  })  : _token = botToken,
        _client = client ?? http.Client();

  final String _token;
  final String channelId;

  /// 메시지에 "스프레드시트에서보기" 링크를 넣으려면 필요하다.
  final String spreadsheetId;
  final http.Client _client;

  Map<String, String> get _auth => <String, String>{
        'Authorization': 'Bearer $_token',
      };

  /// 증빙사진 + 매입 내용을 채널에 올린다.
  Future<void> postEvidence({
    required File image,
    required String filename,
    required DateTime belongDate,
    required String vendor,
    required String description,
    required int totalAmount,
    required String currency,
    required String className,
    required String submittedBy,
    required String driveUrl,
  }) async {
    final comment = buildComment(
      belongDate: belongDate,
      vendor: vendor,
      description: description,
      totalAmount: totalAmount,
      currency: currency,
      className: className,
      submittedBy: submittedBy,
      driveUrl: driveUrl,
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
  }

  /// 채널에 붙는 메시지.
  ///
  /// 한 줄로 요약하고 링크는 아래에 둔다 — `#purchase` 는 흘러가는 채널이라
  /// 스크롤하면서 훑을 수 있어야 한다. 사람이 손으로 던지던 시절의 형태에 맞춘다.
  ///
  /// ```text
  /// 260910 / 드림디포(에이스) / 뽁뽁이 / 8,000원 / 법인(이체)
  /// james@bodit.co
  /// 드라이브에서보기
  /// 스프레드시트에서보기
  /// ```
  @visibleForTesting
  String buildComment({
    required DateTime belongDate,
    required String vendor,
    required String description,
    required int totalAmount,
    required String currency,
    required String className,
    required String submittedBy,
    required String driveUrl,
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
      // Slack 링크 문법은 <url|보일 글자> 다.
      '<$driveUrl|드라이브에서보기>',
      '<${spreadsheetUrl(spreadsheetId)}|스프레드시트에서보기>',
    ].join('\n');
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
