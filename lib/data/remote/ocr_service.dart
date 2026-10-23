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
/// ## 확신도와 사진 품질을 같이 받는다
///
/// 예전엔 값만 받았다(ADR Decision 11 이 확신도 표시를 막았다 — "여기만
/// 확인하세요" 라고 찍으면 나머지를 안 본다는 이유였다). 운영에서 뒤집혔다:
/// 전부 훑으라고 해도 실제로는 안 훑었고, 틀린 값이 그대로 시트에 들어갔다.
///
/// 그래서 **항목별 확신도**와 **사진 품질**을 같이 받는다.
///
/// 사진 품질을 기기에서 미리 재지 않는 이유: 흔들림 판정은 픽셀 분석이
/// 필요한데(라플라시안 분산 등) 영수증은 원래 고대비라 기준값이 기기마다 다르다.
/// **읽을 수 있었는지는 읽어본 쪽이 가장 잘 안다** — 모델에게 묻는 게 정확하다.
/// 호출 한 번 값이지만 잘못 읽은 값을 그대로 제출하는 것보다 싸다.
///
/// ## 비용
///
/// 이미지 토큰 ≈ (가로 × 세로) / 750. 즉 **압축이 곧 비용 절감**이다.
/// 호출 전에 `flutter_image_compress` 로 긴 변을 1600px 정도로 줄인다.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// 사진이 OCR 하기에 괜찮았는지. 모델이 스스로 판정한다.
class ImageQuality {
  const ImageQuality({required this.readable, this.problem});

  /// 항목을 읽어낼 만했는지.
  final bool readable;

  /// 읽기 힘들었던 이유. 사람이 읽을 한국어 한 조각이다 —
  /// 코드값으로 받으면 모델이 새 값을 지어낼 때 화면이 빈다.
  final String? problem;

  static const ok = ImageQuality(readable: true);
}

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
    this.quality = ImageQuality.ok,
    this.confidence = const <String, double>{},
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
      quality: _quality(j['image_quality']),
      confidence: _confidence(j['confidence']),
    );
  }

  static ImageQuality _quality(Object? v) {
    if (v is! Map) return ImageQuality.ok;
    final problem = v['problem'];
    return ImageQuality(
      // 값이 빠지면 "괜찮다" 로 본다 — 스키마가 바뀌었다고 멀쩡한 사진에
      // 다시 찍으라고 하면 아무도 안 믿는다.
      readable: v['readable'] != false,
      problem: problem is String && problem.trim().isNotEmpty
          ? problem.trim()
          : null,
    );
  }

  static Map<String, double> _confidence(Object? v) {
    if (v is! Map) return const <String, double>{};
    return <String, double>{
      for (final e in v.entries)
        if (e.value is num) '${e.key}': (e.value as num).toDouble(),
    };
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

  /// 사진이 읽을 만했는지. 나쁘면 화면이 다시 찍으라고 안내한다.
  final ImageQuality quality;

  /// 항목별 확신도(0.0~1.0). 키는 스키마의 필드명 그대로다
  /// (`belong_date`·`vendor`·`description`·`total_amount`·`card_last4`).
  ///
  /// **없는 키는 "모른다" 지 "확신한다" 가 아니다.** 화면이 그렇게 다룬다 —
  /// 비어 있다고 전부 초록으로 칠하면 경고가 아니라 거짓말이 된다.
  final Map<String, double> confidence;
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
      'image_quality': <String, Object>{
        'type': 'object',
        'description': '이 사진이 읽을 만했는지에 대한 네 판단',
        'properties': <String, Object>{
          'readable': <String, Object>{
            'type': 'boolean',
            'description': '항목들을 읽어낼 만했으면 true',
          },
          'problem': <String, Object>{
            'type': <String>['string', 'null'],
            'description':
                'readable 이 false 일 때만 채운다. 사용자에게 보여줄 **한국어 한 문장**으로 '
                '무엇이 문제인지와 어떻게 다시 찍으면 되는지를 쓴다. '
                '예: "글씨가 흔들려 금액이 안 보입니다. 가까이서 다시 찍어주세요." '
                'readable 이 true 면 null',
          },
        },
        'required': <String>['readable', 'problem'],
        'additionalProperties': false,
      },
      'confidence': <String, Object>{
        'type': 'object',
        'description':
            '항목별 확신도 0.0~1.0. **읽은 글자가 맞다고 얼마나 확신하는지**이지 '
            '값이 그럴듯한지가 아니다. 흐릿하거나 가려졌거나 추측이 섞였으면 낮춘다. '
            '값이 null 인 항목은 0 으로 둔다',
        'properties': <String, Object>{
          'belong_date': <String, Object>{'type': 'number'},
          'vendor': <String, Object>{'type': 'number'},
          'description': <String, Object>{'type': 'number'},
          'total_amount': <String, Object>{'type': 'number'},
          'card_last4': <String, Object>{'type': 'number'},
        },
        'required': <String>[
          'belong_date',
          'vendor',
          'description',
          'total_amount',
          'card_last4',
        ],
        'additionalProperties': false,
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
      'image_quality',
      'confidence',
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
- confidence 는 **읽은 글자가 맞다는 확신**이다. 값이 그럴듯한지가 아니다.
  흐릿하거나 가려졌거나 추측이 섞였으면 낮춰라. null 인 항목은 0 이다.
- image_quality.readable 은 **항목을 제대로 읽어낼 만한 사진이었는지**다.
  흔들림·잘림·어두움·빛번짐으로 금액이나 상호를 못 읽었으면 false 로 두고,
  problem 에 사용자가 바로 행동할 수 있는 한국어 한 문장을 써라.
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
