/// Anthropic Messages API 를 치는 자리. **요청을 만드는 코드는 여기 하나다.**
///
/// Dart 에는 공식 Anthropic SDK 가 없으므로 `POST /v1/messages` 를 직접 친다.
///
/// ## 왜 따로 뺐나
///
/// 호출이 **둘이 됐다** — 증빙을 읽는 OCR(`OcrService`)과 비목을 짐작하는
/// 조언(`CategoryAdvisor`). 요청 만드는 코드를 양쪽에 두면 한쪽만 고쳐진다:
/// 버전 헤더·모델 이름·거절 처리·utf8 디코딩이 전부 같은 자리에 있어야 한다
/// (`anthropic-version` 을 한쪽만 올리면 다른 쪽이 조용히 옛 동작을 한다).
///
/// 여기는 **무엇을 묻는지 모른다.** 스키마와 프롬프트는 부르는 쪽이 들고 있고,
/// 여기는 그걸 실어 보내고 JSON 하나를 돌려주는 일만 한다.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

class AnthropicClient {
  AnthropicClient({required String apiKey, http.Client? client})
    : _apiKey = apiKey,
      _client = client ?? http.Client();

  final String _apiKey;
  final http.Client _client;

  static const _endpoint = 'https://api.anthropic.com/v1/messages';

  /// 두 호출이 **같은 모델**을 쓴다. 영수증을 읽는 일과 그 품목으로 비목을
  /// 가르는 일이 둘 다 한국 회계 맥락을 알아야 하는 일이라 가를 이유가 없다.
  static const model = 'claude-opus-5';

  /// 스키마를 강제해 JSON 객체 하나를 받는다.
  ///
  /// `output_config.format` 이 `json_schema` 를 강제하므로 파싱이 실패하지
  /// 않는다 — 다만 **스키마가 거절되면 400 이다**(지원하지 않는 키워드를
  /// 쓴 경우). 그때는 아래에서 본문을 그대로 들고 던지므로 원인이 보인다.
  ///
  /// [what] 은 실패 문구에 그대로 들어간다(`OCR 실패 (429): …`) —
  /// 사용자가 보는 줄이라 무엇이 실패했는지는 적혀 있어야 한다.
  Future<Map<String, dynamic>> structured({
    required String what,
    required List<Object> content,
    required Map<String, Object> schema,
    int maxTokens = 2048,
    String effort = 'low',
  }) async {
    final body = <String, Object>{
      'model': model,
      'max_tokens': maxTokens,
      'output_config': <String, Object>{
        // 단순 추출·분류라 낮은 effort 로 충분하다. 비용·지연이 같이 준다.
        'effort': effort,
        'format': <String, Object>{'type': 'json_schema', 'schema': schema},
      },
      'messages': <Object>[
        <String, Object>{'role': 'user', 'content': content},
      ],
    };

    final res = await _client.post(
      Uri.parse(_endpoint),
      headers: <String, String>{
        'content-type': 'application/json',
        'x-api-key': _apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: jsonEncode(body),
    );

    if (res.statusCode != 200) {
      throw AnthropicException('$what 실패 (${res.statusCode}): ${res.body}');
    }

    // utf8 로 직접 디코딩한다 — http 의 기본 latin1 해석이 한글을 깬다.
    final decoded =
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;

    // 안전 정책상 거절되면 content 가 비어 있을 수 있다.
    if (decoded['stop_reason'] == 'refusal') {
      throw AnthropicException('$what — 모델이 요청을 거절했습니다.');
    }

    final blocks = (decoded['content'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final text = blocks.where((b) => b['type'] == 'text').firstOrNull?['text'];
    if (text is! String) {
      // 글 덩어리가 아예 없는 응답. 조용히 빈 값으로 넘기지 않는다 —
      // 그러면 호출부가 "모델이 아무것도 못 찾았다" 로 읽는다.
      throw AnthropicException('$what — 응답에 글이 없습니다: ${res.body}');
    }

    return jsonDecode(text) as Map<String, dynamic>;
  }
}

class AnthropicException implements Exception {
  const AnthropicException(this.message);

  final String message;

  @override
  String toString() => message;
}
