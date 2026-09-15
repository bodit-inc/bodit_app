/// 증빙 이미지에서 매입내역 항목을 뽑는다.
///
/// Dart 에는 공식 Anthropic SDK 가 없으므로 `POST /v1/messages` 를 직접 친다.
/// `output_config.format` 으로 JSON 스키마를 강제하므로 파싱이 실패하지 않는다.
///
/// ## 뽑는 것 / 못 뽑는 것
///
/// **비목·분류코드는 여기서 뽑지 않는다.** 영수증에 안 적혀 있다.
/// 그건 과거 이력 추천(`MasterDataRepository` + 시트 조회)이 담당한다.
///
/// ## 부가세를 자동 계산하지 않는다
///
/// 도서 등 면세는 0원이 맞다. 모델에게 **인쇄된 값만 읽으라**고 지시하고,
/// 총액만 있으면 `vatPrinted: false` 로 알려준다. 나눌지는 사용자가 정한다.
///
/// ## 비용
///
/// 이미지 토큰 ≈ (가로 × 세로) / 750. 즉 **압축이 곧 비용 절감**이다.
/// 호출 전에 `flutter_image_compress` 로 긴 변을 1600px 정도로 줄인다.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// OCR 이 읽어낸 값. 못 읽은 필드는 null 이다.
class OcrResult {
  const OcrResult({
    this.belongDate,
    this.vendor,
    this.description,
    this.totalAmount,
    this.supplyAmount,
    this.vatAmount,
    this.cardLast4,
    this.vatPrinted = false,
  });

  factory OcrResult.fromJson(Map<String, dynamic> j) {
    DateTime? date(Object? v) =>
        v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
    int? num_(Object? v) => v is num ? v.toInt() : null;
    String? str(Object? v) =>
        v is String && v.trim().isNotEmpty ? v.trim() : null;

    return OcrResult(
      belongDate: date(j['belong_date']),
      vendor: str(j['vendor']),
      description: str(j['description']),
      totalAmount: num_(j['total_amount']),
      supplyAmount: num_(j['supply_amount']),
      vatAmount: num_(j['vat_amount']),
      cardLast4: str(j['card_last4']),
      vatPrinted: j['vat_printed'] == true,
    );
  }

  final DateTime? belongDate;
  final String? vendor;
  final String? description;
  final int? totalAmount;
  final int? supplyAmount;
  final int? vatAmount;

  /// 뒤 4자리만. 프롬프트에서 앞자리를 아예 읽지 말라고 지시한다.
  final String? cardLast4;

  /// 영수증에 부가세가 **인쇄돼 있었는지**. false 면 총액만 찍힌 것이므로
  /// 사용자에게 "1.1로 나누기" 를 물어본다.
  final bool vatPrinted;
}

class OcrService {
  OcrService({required String apiKey, http.Client? client})
    : _apiKey = apiKey,
      _client = client ?? http.Client();

  final String _apiKey;
  final http.Client _client;

  static const _endpoint = 'https://api.anthropic.com/v1/messages';
  static const _model = 'claude-opus-5';

  /// 응답 스키마. `additionalProperties: false` + `required` 가 있어야 강제된다.
  static const _schema = <String, Object>{
    'type': 'object',
    'properties': <String, Object>{
      'belong_date': <String, Object>{
        'type': <String>['string', 'null'],
        'description': '영수증에 인쇄된 거래일. YYYY-MM-DD. 없으면 null',
      },
      'vendor': <String, Object>{
        'type': <String>['string', 'null'],
        'description': '상호명. 지점명이 있으면 포함',
      },
      'description': <String, Object>{
        'type': <String>['string', 'null'],
        'description': '구매 품목 요약. 여러 개면 대표 품목 + 외 N건',
      },
      'total_amount': <String, Object>{
        'type': <String>['integer', 'null'],
        'description': '결제 총액(원). 쉼표 없이 숫자만',
      },
      'supply_amount': <String, Object>{
        'type': <String>['integer', 'null'],
        'description': '공급가액. 인쇄돼 있을 때만. 없으면 null',
      },
      'vat_amount': <String, Object>{
        'type': <String>['integer', 'null'],
        'description': '부가세. 인쇄돼 있을 때만. 계산하지 말 것. 없으면 null',
      },
      'vat_printed': <String, Object>{
        'type': 'boolean',
        'description': '부가세가 영수증에 실제로 인쇄돼 있었는지',
      },
      'card_last4': <String, Object>{
        'type': <String>['string', 'null'],
        'description': '카드번호 뒤 4자리만. 앞자리는 읽지 말 것',
      },
    },
    'required': <String>[
      'belong_date',
      'vendor',
      'description',
      'total_amount',
      'supply_amount',
      'vat_amount',
      'vat_printed',
      'card_last4',
    ],
    'additionalProperties': false,
  };

  static const _prompt = '''
한국 영수증·매출전표 이미지다. 아래 규칙대로 항목을 읽어라.

- **인쇄된 값만 읽는다.** 추론하거나 계산하지 마라.
- 부가세: 영수증에 적혀 있을 때만 채운다. 총액만 있으면 vat_amount 는 null,
  vat_printed 는 false 로 둔다. **총액을 1.1로 나누지 마라** — 면세 품목(도서 등)이
  있어서 틀린다.
- 카드번호는 **뒤 4자리만** 읽는다. 앞자리는 읽지도 마라.
- 금액은 쉼표를 빼고 정수로.
- 읽을 수 없는 항목은 null 로 둔다. 지어내지 마라.
''';

  /// 이미지 한 장에서 항목을 뽑는다.
  ///
  /// [mediaType] 은 `image/jpeg` · `image/png` 중 하나.
  Future<OcrResult> extract({
    required Uint8List imageBytes,
    String mediaType = 'image/jpeg',
  }) async {
    final body = <String, Object>{
      'model': _model,
      'max_tokens': 2048,
      // 단순 추출이라 낮은 effort 로 충분하다. 비용·지연이 같이 준다.
      'output_config': <String, Object>{
        'effort': 'low',
        'format': <String, Object>{'type': 'json_schema', 'schema': _schema},
      },
      'messages': <Object>[
        <String, Object>{
          'role': 'user',
          'content': <Object>[
            <String, Object>{
              'type': 'image',
              'source': <String, Object>{
                'type': 'base64',
                'media_type': mediaType,
                'data': base64Encode(imageBytes),
              },
            },
            <String, Object>{'type': 'text', 'text': _prompt},
          ],
        },
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
      throw OcrException('OCR 실패 (${res.statusCode}): ${res.body}');
    }

    // utf8 로 직접 디코딩한다 — http 의 기본 latin1 해석이 한글을 깬다.
    final decoded =
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;

    // 안전 정책상 거절되면 content 가 비어 있을 수 있다.
    if (decoded['stop_reason'] == 'refusal') {
      throw const OcrException('모델이 요청을 거절했습니다.');
    }

    final content = decoded['content'] as List<dynamic>;
    final text =
        content.cast<Map<String, dynamic>>().firstWhere(
              (b) => b['type'] == 'text',
            )['text']
            as String;

    return OcrResult.fromJson(jsonDecode(text) as Map<String, dynamic>);
  }
}

class OcrException implements Exception {
  const OcrException(this.message);

  final String message;

  @override
  String toString() => message;
}
