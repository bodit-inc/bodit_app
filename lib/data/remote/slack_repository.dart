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

import 'package:http/http.dart' as http;

class SlackRepository {
  SlackRepository({
    required String botToken,
    required this.channelId,
    http.Client? client,
  })  : _token = botToken,
        _client = client ?? http.Client();

  final String _token;
  final String channelId;
  final http.Client _client;

  Map<String, String> get _auth => <String, String>{
        'Authorization': 'Bearer $_token',
      };

  /// 증빙사진 + 매입 내용을 채널에 올린다.
  Future<void> postEvidence({
    required File image,
    required String filename,
    required String vendor,
    required int totalAmount,
    required String expenseCategory,
    required String description,
    required String cardLast4,
    required String submittedBy,
    required String driveUrl,
  }) async {
    final comment = _comment(
      vendor: vendor,
      totalAmount: totalAmount,
      expenseCategory: expenseCategory,
      description: description,
      cardLast4: cardLast4,
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

  String _comment({
    required String vendor,
    required int totalAmount,
    required String expenseCategory,
    required String description,
    required String cardLast4,
    required String submittedBy,
    required String driveUrl,
  }) {
    final amount = totalAmount.toString().replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+$)'),
          (m) => '${m[1]},',
        );
    return '*$vendor* · $amount원\n'
        '$expenseCategory · $description · 카드 ••••$cardLast4\n'
        '등록 $submittedBy\n'
        '<$driveUrl|Drive 에서 보기>';
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
