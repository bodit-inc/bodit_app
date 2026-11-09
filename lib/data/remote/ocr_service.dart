/// 증빙 이미지에서 매입내역 항목을 뽑는다.
///
/// 요청을 만드는 일은 `AnthropicClient` 가 한다 — 여기는 **무엇을 묻는지**
/// (스키마와 프롬프트)와 받은 값을 어떻게 읽는지만 들고 있다.
/// `output_config.format` 으로 JSON 스키마를 강제하므로 파싱이 실패하지 않는다.
///
/// ## 뽑는 것 / 못 뽑는 것
///
/// **비목·분류코드는 여기서 뽑지 않는다.** 영수증에 안 적혀 있다.
/// 비목은 과거 이력 추천(`VendorSuggestion`)이 1차이고, 그게 비면
/// **별도 호출**이 품목을 보고 짐작한다(`CategoryAdvisor`).
///
/// **같은 요청에 합치지 않는다.** 이 프롬프트는 "인쇄된 값만 읽어라,
/// 추론하지 마라" 로 일관돼야 한다 — 여기에 "비목은 추측해라" 를 붙이면
/// 모델이 다른 칸도 추측하기 시작한다. 금액을 추론한 영수증은 사람이
/// 알아채지 못한다.
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

import 'package:bodit_app/data/remote/anthropic.dart';
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
    this.spendTime,
    this.vendor,
    this.description,
    this.totalAmount,
    this.supplyAmount,
    this.vatAmount,
    this.cardNumber,
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
      spendTime: str(j['spend_time']),
      vendor: str(j['vendor']),
      description: str(j['description']),
      totalAmount: num_(j['total_amount']),
      supplyAmount: num_(j['supply_amount']),
      vatAmount: num_(j['vat_amount']),
      cardNumber: str(j['card_number']),
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

  /// 영수증에 **인쇄된** 결제 시각, `19:24` 꼴. 안 찍혀 있으면 null.
  ///
  /// 시트에는 안 들어간다(시간 컬럼이 없다). **내역을 짐작하는 재료**다 —
  /// 식당 영수증의 `19:24` 는 그 건이 저녁식사라는 뜻이고, 그게 회계
  /// 담당자가 읽고 싶은 내역이다(`EntryAdvisor`).
  final String? spendTime;

  final String? vendor;
  final String? description;
  final int? totalAmount;
  final int? supplyAmount;
  final int? vatAmount;

  /// 카드번호 **전체**, 영수증에 인쇄된 대로. 가려진 자리는 `*` 로 들어온다
  /// (`5531-46**-****-3927`). 앞자리를 같이 받는 이유는
  /// `card_repository.dart` 의 "카드번호는 전체로 대조한다" 에 적어뒀다.
  final String? cardNumber;

  /// 영수증에 부가세가 **인쇄돼 있었는지**. false 면 총액만 찍힌 것이므로
  /// 사용자에게 "1.1로 나누기" 를 물어본다.
  final bool vatPrinted;

  /// 사진이 읽을 만했는지. 나쁘면 화면이 다시 찍으라고 안내한다.
  final ImageQuality quality;

  /// 항목별 확신도(0.0~1.0). 키는 스키마의 필드명 그대로다
  /// (`belong_date`·`vendor`·`description`·`total_amount`·`card_number`).
  ///
  /// **없는 키는 "모른다" 지 "확신한다" 가 아니다.** 화면이 그렇게 다룬다 —
  /// 비어 있다고 전부 초록으로 칠하면 경고가 아니라 거짓말이 된다.
  final Map<String, double> confidence;
}

class OcrService {
  OcrService({required String apiKey, http.Client? client})
    : _api = AnthropicClient(apiKey: apiKey, client: client);

  final AnthropicClient _api;

  /// 응답 스키마. `additionalProperties: false` + `required` 가 있어야 강제된다.
  static const _schema = <String, Object>{
    'type': 'object',
    'properties': <String, Object>{
      'belong_date': <String, Object>{
        'type': <String>['string', 'null'],
        'description': '영수증에 인쇄된 거래일. YYYY-MM-DD. 없으면 null',
      },
      'spend_time': <String, Object>{
        'type': <String>['string', 'null'],
        'description':
            '영수증에 인쇄된 결제 시각. `HH:MM` 24시간제로. '
            '인쇄돼 있지 않으면 null — **날짜에서 지어내지 말 것**',
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
      'card_number': <String, Object>{
        'type': <String>['string', 'null'],
        'description':
            '카드번호 **전체**를 인쇄된 대로. 앞자리도 같이 읽는다 — '
            '앱이 앞자리까지 대조해서 카드를 찾는다. '
            '가려진 자리는 **보이는 대로** 적는다("5531-46**-****-3927"·"766*"). '
            '가려진 자리를 지어내거나 빼고 적지 말 것 — '
            '자리 수가 맞아야 앱이 카드를 찾는다. '
            '구분자는 아무 모양이어도 된다(앱이 "-" 로 모은다). '
            '뒤 4자리만 인쇄된 영수증이면 그 네 자리만 적는다',
      },
      'image_quality': <String, Object>{
        'type': 'object',
        'description': '이 사진이 읽을 만했는지에 대한 네 판단',
        'properties': <String, Object>{
          'readable': <String, Object>{
            'type': 'boolean',
            'description':
                '항목들을 읽어낼 만했으면 true. 기준은 **다시 찍으면 나아지는가** 하나다. '
                '사진 상태(흔들림·초점·노출·빛번짐·잘림)와 **가림**(손가락·그림자·다른 종이·접힘)은 '
                '다시 찍으면 나아지므로 false. '
                '**카드번호 마스킹(`****`·`766*`)은 영수증에 그렇게 인쇄된 것이라 '
                '다시 찍어도 같다 — true 로 둔다.** '
                '영수증에 원래 없는 항목(면세라 부가세 없음·현금이라 카드번호 없음)도 true 다',
          },
          'problem': <String, Object>{
            'type': <String>['string', 'null'],
            'description':
                'readable 이 false 일 때만 채운다. 사용자에게 보여줄 **한국어 한 문장**으로 '
                '무엇이 문제인지와 어떻게 다시 찍으면 되는지를 쓴다. '
                '가려진 경우에는 **무엇이 어느 항목을 가렸는지** 집어서 말한다 — '
                '어디를 치워야 하는지 알아야 다시 찍을 수 있다. '
                '**다시 찍어서 나아질 수 있는 것만 쓴다.** 카드번호가 마스킹돼 있다는 말은 '
                '쓰지 않는다 — 사용자가 할 수 있는 일이 없다. '
                '예: "글씨가 흔들려 금액이 안 보입니다. 가까이서 다시 찍어주세요." '
                '예: "손가락이 금액을 가렸습니다. 손을 치우고 다시 찍어주세요." '
                '예: "영수증이 접혀 상호가 안 보입니다. 펴서 다시 찍어주세요." '
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
          'card_number': <String, Object>{'type': 'number'},
        },
        'required': <String>[
          'belong_date',
          'vendor',
          'description',
          'total_amount',
          'card_number',
        ],
        'additionalProperties': false,
      },
    },
    'required': <String>[
      'belong_date',
      'spend_time',
      'vendor',
      'description',
      'total_amount',
      'supply_amount',
      'vat_amount',
      'vat_printed',
      'card_number',
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
- 카드번호는 **전체를 인쇄된 대로** 읽는다. 앞자리도 같이 읽어라 —
  앞자리가 카드사·상품이 갈리는 자리라, 앱이 전체로 대조해 카드를 찾는다.
  가려진 자리는 보이는 대로 적어라 — `5531-46**-****-3927`·`766*`·`76*9`.
  **자리 수를 맞춰라.** 가려진 자리를 빼고 `5531463927` 이라고 적으면 앱이
  카드를 찾지 못한다. 지어내서 채우는 것도 안 된다.
  구분자는 아무 모양이어도 된다 — 앱이 `-` 로 모은다.
  영수증에 뒤 4자리만 인쇄돼 있으면 그 네 자리만 적어라.
- 시각(spend_time)은 **인쇄돼 있을 때만** `HH:MM` 로. 날짜만 찍혀 있으면 null 이다 —
  이 값은 "저녁에 쓴 건" 같은 판단에 쓰이므로 지어내면 틀린 내역이 된다.
- 금액은 쉼표를 빼고 정수로.
- 읽을 수 없는 항목은 null 로 둔다. 지어내지 마라.
- confidence 는 **읽은 글자가 맞다는 확신**이다. 값이 그럴듯한지가 아니다.
  흐릿하거나 가려졌거나 추측이 섞였으면 낮춰라. null 인 항목은 0 이다.
- image_quality.readable 의 기준은 **하나다: 다시 찍으면 나아지는가.**
  사용자가 할 수 있는 일은 다시 찍는 것뿐이다. 다시 찍어도 똑같을 문제로
  false 를 주면, 사용자는 고칠 수 없는 안내를 보고 같은 사진을 또 찍는다.
- 그 기준으로, 아래 중 하나로 금액·상호·날짜를 못 읽었으면 false 로 두고,
  problem 에 사용자가 바로 행동할 수 있는 한국어 한 문장을 써라.
  - 사진 상태: 흔들림 · 초점 안 맞음 · 어두움 · 빛번짐 · 잘림
  - **가림**: 손가락·손·그림자·다른 종이·스티커가 항목을 덮었거나,
    영수증이 접혀서 그 줄이 안 보이는 경우
- **가림을 특히 조심해라.** 사진 자체는 선명한데 손가락이 금액만 덮고 있으면
  "읽을 만한 사진" 처럼 보인다. 하지만 그 항목은 **영수증에 적혀 있는데 우리가
  못 읽은 것**이다. 그 항목을 null 로 두고 readable 을 true 로 두지 마라 —
  사용자는 빈 칸만 보고 왜 비었는지 모른 채 손으로 채운다. 다시 찍으면 될 일인데.
  **가려서 못 읽었으면 readable 은 false 다.**
- 반대로 **영수증에 원래 그렇게 인쇄된 것은 가림이 아니다.**
  - **카드번호 마스킹이 그렇다.** `5531-46**-****-3927` 이나 `766*` 처럼
    찍혀 있으면 그게 원본이다. **다시 찍어도 `*` 는 `*` 다.** 보이는 대로
    적고 readable 은 true 로 둔다 — 가려졌다고 false 를 주면 사용자는
    아무리 잘 찍어도 같은 안내를 다시 본다
  - 면세 영수증에 부가세가 없는 것, 현금으로 결제해 카드번호가 없는 것도
    정상이다
  그걸로 readable 을 false 로 두면 멀쩡한 사진에 다시 찍기가 뜨고, 경고가
  잦아지면 정작 흔들린 사진의 경고도 같이 무시된다.
''';

  /// 이미지 한 장에서 항목을 뽑는다.
  ///
  /// [mediaType] 은 `image/jpeg` · `image/png` 중 하나.
  Future<OcrResult> extract({
    required Uint8List imageBytes,
    String mediaType = 'image/jpeg',
  }) async {
    final json = await _api.structured(
      what: 'OCR',
      schema: _schema,
      content: <Object>[
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
    );

    return OcrResult.fromJson(json);
  }
}
