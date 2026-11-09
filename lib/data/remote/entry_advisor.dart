/// 영수증에서 읽은 것으로 **비목과 내역을 짐작한다.**
///
/// 둘 다 영수증에 그렇게 적혀 있지 않은 값이다:
///
///   - **비목**은 아예 인쇄되지 않는다
///   - **내역**은 품목명이 찍혀 있을 뿐이다. 회계 담당자가 읽고 싶은 것은
///     품목명이 아니라 "무슨 건인가" 다 — `된장찌개 2, 공기밥 2` 가 아니라
///     `저녁식사` 다. 합계만 찍힌 영수증이면 품목명조차 없다
///
/// ## 왜 모델에게 묻는가
///
/// 비목의 1차 출처는 과거 이력이다(`VendorSuggestion`) — 기록이라 짐작보다
/// 세다. 글자가 겹치는 과거 행으로도 찾아본다(`CategoryGuess`). 그래도
/// `멀티탭 3구 1.5M` 처럼 처음 사는 물건은 걸릴 행이 하나도 없다.
///
/// 내역은 과거 이력으로 **메울 수가 없다.** 지난 값을 그대로 넣으면 9월에
/// 8월 것이 조용히 들어간다(그래서 후보 칩으로만 띄운다). 이 건의 내역은
/// 이 영수증에서 읽어야 하고, 읽을 재료는 업체명·품목·금액·**시각**이다 —
/// `더좋은밥상 · 19:24 · 32,000원` 이면 저녁식사다.
///
/// 사람은 그 글자만 보고 안다. **읽어서 아는 일이라 읽을 수 있는 쪽에 묻는다.**
///
/// ## 지키는 것 다섯
///
/// 1. **OCR 과 같은 요청에 합치지 않는다.** OCR 프롬프트는 "인쇄된 값만
///    읽어라, 추론하지 마라" 로 일관돼야 한다 — 거기에 "비목·내역은 추측해라"
///    를 붙이면 모델이 금액도 추론하기 시작하고, 추론된 금액은 사람이 못
///    알아챈다. 그래서 별도 호출이고 **이미지를 안 보낸다**(글자만)
/// 2. **이미 아는 칸은 묻지 않는다.** 비목이 이력으로 채워졌으면 비목은 묻지
///    않고 **그 값을 알려준다** — 복리후생비로 잡힌 식당이면 내역은 식사다.
///    인쇄된 품목이 있으면 내역도 묻지 않는다(그건 사실이다)
/// 3. **비목은 마스터 밖의 이름이 나올 수 없다.** 스키마의 `enum` 으로 박는다
/// 4. **내역은 구체적으로 지어내지 않는다.** 시각으로 `저녁식사` 까지는
///    가지만, 누구와 무슨 목적이었는지는 영수증에 없다 — `거래처 미팅` 은
///    그럴듯한 거짓이고, 그런 행은 아무도 못 알아챈다
/// 5. **비목은 칸을 채우지 않고 칩으로만 띄운다.** 내역은 비어 있을 때만
///    채우고 **짐작이라고 표시한다**(`EntryDraft.descriptionIsGuess`) —
///    비면 `운영팀 확인 요청` 으로 들어가서 담당자가 되물어야 하는 칸이라,
///    표시된 짐작이 빈 칸보다 낫다
library;

import 'package:bodit_app/data/remote/anthropic.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 모델이 짐작한 것들. 묻지 않은 칸은 비어 있다.
@immutable
class EntryHint {
  const EntryHint({
    this.categories = const <String>[],
    this.descriptions = const <String>[],
    this.categoryReason,
  });

  /// 그럴듯한 비목, **그럴듯한 것부터.** 전부 `_비목마스터` 안의 이름이다.
  final List<String> categories;

  /// 그럴듯한 내역, **그럴듯한 것부터.** 첫 값이 칸에 들어간다.
  final List<String> descriptions;

  /// 비목을 왜 그렇게 봤는지 한국어 한 문장. 화면이 칩 아래에 보여준다.
  ///
  /// **내역 쪽에는 이 줄이 없다.** 내역은 칸에 값으로 들어가고, 근거는
  /// 화면이 아는 사실(`19:24 결제`)로 적는다 — 모델이 쓴 설명을 값 옆에
  /// 또 붙이면 읽을 것만 늘어난다.
  final String? categoryReason;

  bool get isEmpty => categories.isEmpty && descriptions.isEmpty;
}

class EntryAdvisor {
  EntryAdvisor({required String apiKey, http.Client? client})
    : _api = AnthropicClient(apiKey: apiKey, client: client);

  final AnthropicClient _api;

  /// 칩으로 띄울 후보 수의 상한.
  ///
  /// 셋을 넘기면 "그나마 이거일 것 같은 것" 이 아니라 **짧은 목록**이 된다
  /// (`CategoryGuess.maxCandidates` 와 같은 이유).
  static const maxCandidates = 3;

  /// [categories] 는 `_비목마스터` 에서 읽은 이름들이다. **스키마에 그대로
  /// 박아서** 모델이 그 밖의 이름을 못 쓰게 한다.
  ///
  /// [knownCategory] 가 있으면 비목은 묻지 않고 **재료로 넘긴다.**
  /// [printedDescription] 은 영수증에 인쇄된 품목명이다 — 있으면 내역도
  /// 묻지 않는다(인쇄된 값이 사실이고, 짐작이 사실을 덮을 자리는 없다).
  /// [pastDescriptions] 는 이 업체로 과거에 쓴 내역이다. 같은 일을 회사가
  /// 어떻게 적어왔는지가 가장 좋은 재료다 — `식대` 로 적어온 회사에 `저녁식사`
  /// 를 권하면 담당자가 다시 고친다.
  ///
  /// 물을 것이 없으면 **호출하지 않고** null 이다.
  Future<EntryHint?> suggest({
    required List<String> categories,
    bool needCategory = true,
    bool needDescription = true,
    String? knownCategory,
    String? vendor,
    String? printedDescription,
    String? spendTime,
    int? totalAmount,
    String currency = 'KRW',
    List<String> pastDescriptions = const <String>[],
  }) async {
    // 비목을 물으려면 고를 목록이 있어야 한다. 마스터를 못 읽었으면 비목은
    // 못 묻지만 **내역은 물을 수 있다** — 그쪽은 자유 입력 칸이다.
    final askCategory = needCategory && categories.isNotEmpty;
    if (!askCategory && !needDescription) return null;

    // 업체명도 품목도 없으면 금액·시각만으로는 아무것도 못 짐작한다.
    if ((vendor ?? '').isEmpty && (printedDescription ?? '').isEmpty) {
      return null;
    }

    final facts = <String>[
      if ((vendor ?? '').isNotEmpty) '업체명: $vendor',
      if ((printedDescription ?? '').isNotEmpty)
        '영수증에 인쇄된 품목: $printedDescription',
      if (totalAmount != null) '총금액: $totalAmount $currency',
      if ((spendTime ?? '').isNotEmpty) '결제 시각: $spendTime',
      if ((knownCategory ?? '').isNotEmpty) '이미 정해진 비목: $knownCategory',
      if (pastDescriptions.isNotEmpty)
        '이 업체로 과거에 쓴 내역: ${pastDescriptions.join(' · ')}',
    ];

    final json = await _api.structured(
      what: '비목·내역 짐작',
      // 후보 몇 개와 한 문장이면 충분하다. 넉넉히 줘도 쓸 일이 없고,
      // 모자라면 JSON 이 잘려서 통째로 버리게 된다.
      maxTokens: 512,
      schema: _schema(
        categories: categories,
        askCategory: askCategory,
        askDescription: needDescription,
      ),
      content: <Object>[
        <String, Object>{
          'type': 'text',
          'text': '$_prompt\n${facts.join('\n')}',
        },
      ],
    );

    final picked = askCategory
        ? _strings(json['categories'], allowed: categories.toSet())
        : const <String>[];
    final descriptions = needDescription
        ? _strings(json['descriptions'])
        : const <String>[];
    if (picked.isEmpty && descriptions.isEmpty) return null;

    final reason = json['category_reason'];
    return EntryHint(
      categories: picked,
      descriptions: descriptions,
      categoryReason: picked.isNotEmpty && reason is String && reason.trim().isNotEmpty
          ? reason.trim()
          : null,
    );
  }

  /// 문자열 배열을 추려 읽는다 — 중복·빈 값·[allowed] 밖의 값을 버리고
  /// [maxCandidates] 개까지.
  ///
  /// 비목은 `enum` 이 이미 막지만 **한 번 더 걸러낸다** — 스키마를 못 지키는
  /// 응답(거절·잘림)이나 마스터가 그 사이 바뀐 경우가 있고, 그때 들어온
  /// 이름을 칩으로 띄우면 시트에 없는 비목이 제출된다.
  static List<String> _strings(Object? raw, {Set<String>? allowed}) {
    if (raw is! List) return const <String>[];
    final out = <String>[];
    for (final v in raw) {
      if (v is! String) continue;
      final s = v.trim();
      if (s.isEmpty || out.contains(s)) continue;
      if (allowed != null && !allowed.contains(s)) continue;
      out.add(s);
      if (out.length == maxCandidates) break;
    }
    return out;
  }

  static Map<String, Object> _schema({
    required List<String> categories,
    required bool askCategory,
    required bool askDescription,
  }) {
    return <String, Object>{
      'type': 'object',
      'properties': <String, Object>{
        if (askCategory) ...<String, Object>{
          'categories': <String, Object>{
            'type': 'array',
            'description':
                '그럴듯한 비목, **가장 그럴듯한 것부터.** 최대 3개. '
                '억지로 채우지 말 것 — 짐작이 안 되면 빈 배열',
            // 여기가 핵심이다. 마스터를 그대로 박아서 **그 밖의 이름이
            // 나올 수 없게** 한다.
            'items': <String, Object>{'type': 'string', 'enum': categories},
            // `maxItems` 는 쓰지 않는다 — API 가 거절한다(400:
            // "For 'array' type, property 'maxItems' is not supported").
            // 개수는 위 설명과 프롬프트로 말하고, 넘어오면 코드에서 자른다.
          },
          'category_reason': <String, Object>{
            'type': <String>['string', 'null'],
            'description':
                '비목을 왜 그렇게 봤는지 **한국어 한 문장, 40자 안쪽.** '
                '품목을 집어서 말한다("멀티탭은 사무실에서 쓰는 비품이다."). '
                '비목 이름을 되풀이하지 말 것 — 칩에 이미 적혀 있다. '
                'categories 가 비면 null',
          },
        },
        if (askDescription)
          'descriptions': <String, Object>{
            'type': 'array',
            'description':
                '매입내역의 **내역** 칸에 들어갈 말, 가장 그럴듯한 것부터 최대 3개. '
                '회계 담당자가 읽는 칸이라 품목명 나열이 아니라 "무슨 건인가" 다 '
                '("저녁식사"·"사무실 비품"). 2~8자. '
                '짐작이 안 되면 빈 배열 — 비워두는 길이 있다',
          },
      },
      'required': <String>[
        if (askCategory) ...<String>['categories', 'category_reason'],
        if (askDescription) 'descriptions',
      ],
      'additionalProperties': false,
    };
  }

  static const _prompt = '''
한국 회사의 매입내역을 채우는 일이다. 증빙에서 읽은 값으로 빈 칸을 짐작해라.

- 스키마에 있는 칸만 답한다. 이미 정해진 값은 재료로 쓰고 다시 답하지 않는다.
- **품목이 무엇인지**로 판단해라. 업체명은 보조다 — 문고에서 간식을 살 수도 있다.
- 금액도 본다. 같은 물건이라도 소모품으로 쓰는 금액과 자산으로 잡는 금액이 다르다.

비목(categories):
- 고를 수 있는 이름은 스키마의 목록(enum)에 있는 것뿐이다. 새 이름을 지어내지 마라.
- **억지로 3개를 채우지 마라.** 하나만 떠오르면 하나만, 아무것도 못 짚겠으면
  빈 배열이다. 그럴듯하지 않은 것까지 끼우면 사용자가 칩 전체를 안 믿는다.
- 확실하지 않아도 **그럴듯한 쪽부터 적는 것**이 비워두는 것보다 낫다 —
  사용자는 칩을 고르거나 무시할 수 있지만, 비어 있으면 34개를 처음부터 훑는다.
- category_reason 은 **한 문장, 40자 안쪽.** 칩 아래 한 줄로 들어가는 글이라
  길면 버튼이 화면 밖으로 밀린다. 평어체로 쓴다("…비품이다").

내역(descriptions):
- **회계 담당자가 읽을 한 마디**다. 품목명을 그대로 옮기지 마라 —
  `된장찌개 2, 공기밥 2` 가 아니라 `저녁식사` 다.
- **시각이 주어지면 쓴다.** 식당에서 11~14시면 점심식사, 17~21시면 저녁식사다.
  시각이 없으면 `식사` 처럼 때를 말하지 않는 쪽으로 적는다 — 없는 사실을
  붙이면 안 된다.
- `이 업체로 과거에 쓴 내역` 이 주어지면 **그 말투를 따른다.** 회사가 `식대`
  로 적어온 곳에 `저녁식사` 를 권하면 담당자가 다시 고친다.
- **목적이나 사람을 지어내지 마라.** `거래처 미팅`·`팀 회식`·`대표님 식사` 는
  영수증에 없는 사실이다. 그럴듯한 거짓은 아무도 못 알아챈다 —
  모르면 `식사` 처럼 넓은 말로 적는다.
- 짐작이 안 되면 빈 배열이다. 그 칸은 비워두면 `운영팀 확인 요청` 으로
  들어가므로, 틀린 말을 적는 것보다 비우는 쪽이 낫다.
''';
}
