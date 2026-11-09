/// `EntryAdvisor` — 영수증을 읽고 비목·내역을 짐작하는 호출.
///
/// 네트워크는 `MockClient` 로 막는다. 여기서 고정하는 것은 **요청이 마스터를
/// 제대로 박는지**와 **돌아온 이름을 한 번 더 걸러내는지**다. 둘 중 하나라도
/// 틀리면 마스터에 없는 비목이 칩으로 뜨고, 그걸 눌러 제출한 행은
/// append-only 라 되돌릴 수 없다.
library;

import 'dart:convert';

import 'package:bodit_app/data/remote/entry_advisor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _master = <String>[
  '사무용품비',
  '소모품비',
  '장비구입비',
  '도서인쇄비',
  '복리후생비',
];

/// 모델이 돌려준 JSON 을 그대로 실어 보내는 응답.
///
/// **bodyBytes 에 utf8 로 넣는다** — `http.Response(String)` 은 latin1 로
/// 굽기 때문에 한글이 깨지고, 그러면 실제 응답과 다른 것을 테스트하게 된다.
http.Response _reply(Map<String, Object?> answer) => http.Response.bytes(
  utf8.encode(
    jsonEncode(<String, Object?>{
      'content': <Object>[
        <String, Object>{'type': 'text', 'text': jsonEncode(answer)},
      ],
    }),
  ),
  200,
);

void main() {
  test('마스터를 스키마의 enum 으로 박는다 — 모델이 그 밖의 이름을 못 쓰게 하는 유일한 장치', () async {
    Map<String, dynamic>? sent;
    final advisor = EntryAdvisor(
      apiKey: 'k',
      client: MockClient((req) async {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return _reply(<String, Object?>{
          'categories': <String>['사무용품비'],
          'category_reason': '멀티탭은 사무실 비품이다.',
          'descriptions': <String>['멀티탭'],
        });
      }),
    );

    await advisor.suggest(
      categories: _master,
      vendor: '다이소 역삼점',
      printedDescription: '멀티탭 3구 1.5M',
      totalAmount: 9900,
    );

    final schema =
        ((sent!['output_config'] as Map)['format'] as Map)['schema']
            as Map<String, dynamic>;
    final items =
        ((schema['properties'] as Map)['categories'] as Map)['items'] as Map;
    expect(items['enum'], _master);
    // **`maxItems` 를 넣으면 API 가 400 으로 거절한다**(실제로 그랬다:
    // "For 'array' type, property 'maxItems' is not supported").
    // 개수는 설명과 프롬프트로 말하고 코드에서 자른다.
    expect((schema['properties'] as Map)['categories'], isNot(contains('maxItems')));

    // 품목·금액이 요청에 실려야 한다 — 금액이 소모품과 장비를 가른다.
    final text =
        ((sent!['messages'] as List).first as Map)['content'] as List<dynamic>;
    final prompt = (text.first as Map)['text'] as String;
    expect(prompt, contains('멀티탭 3구 1.5M'));
    expect(prompt, contains('9900'));
  });

  test('이름과 이유를 읽어온다', () async {
    final advisor = EntryAdvisor(
      apiKey: 'k',
      client: MockClient(
        (_) async => _reply(<String, Object?>{
          'categories': <String>['소모품비', '사무용품비'],
          'category_reason': '만원 이하 멀티탭이라 소모품으로 처리한다.',
          'descriptions': <String>['사무실 비품'],
        }),
      ),
    );

    final hint = await advisor.suggest(
      categories: _master,
      printedDescription: '멀티탭 3구 1.5M',
    );

    expect(hint!.categories, <String>['소모품비', '사무용품비']);
    expect(hint.categoryReason, '만원 이하 멀티탭이라 소모품으로 처리한다.');
  });

  test('마스터 밖의 이름은 버린다 — enum 을 못 지킨 응답이 들어올 자리가 남아 있다', () async {
    final advisor = EntryAdvisor(
      apiKey: 'k',
      client: MockClient(
        (_) async => _reply(<String, Object?>{
          // `사무비품비` 는 그럴듯하지만 마스터에 없다. 시트의 비목 칸은
          // 마스터의 이름이어야 한다.
          'categories': <String>['사무비품비', '소모품비', '소모품비'],
          'category_reason': null,
          'descriptions': <String>[],
        }),
      ),
    );

    final hint = await advisor.suggest(
      categories: _master,
      printedDescription: '멀티탭',
    );

    // 중복도 지운다 — 같은 칩이 두 개 뜨면 두 가지인 줄 읽힌다.
    expect(hint!.categories, <String>['소모품비']);
    expect(hint.categoryReason, isNull);
  });

  test('셋을 넘기면 자른다 — 더 띄우면 아래 전체 목록과 하는 일이 같아진다', () async {
    final advisor = EntryAdvisor(
      apiKey: 'k',
      client: MockClient(
        (_) async => _reply(<String, Object?>{
          'categories': _master,
          'category_reason': '아무 말',
          'descriptions': <String>[],
        }),
      ),
    );

    final hint = await advisor.suggest(categories: _master, printedDescription: '무엇');

    expect(hint!.categories.length, EntryAdvisor.maxCandidates);
    expect(hint.categories.first, _master.first);
  });

  test('짐작이 안 됐다고 하면 null — 억지로 채우지 않는다', () async {
    final advisor = EntryAdvisor(
      apiKey: 'k',
      client: MockClient(
        (_) async => _reply(<String, Object?>{
          'categories': <String>[],
          'category_reason': null,
          'descriptions': <String>[],
        }),
      ),
    );

    expect(
      await advisor.suggest(categories: _master, printedDescription: '읽을 수 없는 글자'),
      isNull,
    );
  });

  group('내역 짐작', () {
    test('이미 아는 칸은 스키마에서 빠진다 — 비목이 정해졌으면 다시 묻지 않는다', () async {
      Map<String, dynamic>? sent;
      final advisor = EntryAdvisor(
        apiKey: 'k',
        client: MockClient((req) async {
          sent = jsonDecode(req.body) as Map<String, dynamic>;
          return _reply(<String, Object?>{
            'descriptions': <String>['저녁식사', '식사'],
          });
        }),
      );

      final hint = await advisor.suggest(
        categories: _master,
        needCategory: false,
        knownCategory: '복리후생비',
        vendor: '더좋은밥상',
        spendTime: '19:24',
        totalAmount: 32000,
        pastDescriptions: const <String>['점심식사'],
      );

      final schema =
          ((sent!['output_config'] as Map)['format'] as Map)['schema']
              as Map<String, dynamic>;
      final props = schema['properties'] as Map;
      expect(props.containsKey('descriptions'), isTrue);
      // 비목을 다시 물으면 모델이 이력이 정한 값과 다른 것을 고를 수 있다.
      expect(props.containsKey('categories'), isFalse);
      expect(schema['required'], <String>['descriptions']);

      // 정해진 비목·시각·과거 말투가 **재료로** 들어간다.
      final content =
          ((sent!['messages'] as List).first as Map)['content'] as List<dynamic>;
      final prompt = (content.first as Map)['text'] as String;
      expect(prompt, contains('이미 정해진 비목: 복리후생비'));
      expect(prompt, contains('결제 시각: 19:24'));
      expect(prompt, contains('점심식사'));

      expect(hint!.descriptions, <String>['저녁식사', '식사']);
      expect(hint.categories, isEmpty);
    });

    test('마스터를 못 읽어도 내역은 묻는다 — 자유 입력 칸이라 목록이 필요 없다', () async {
      final advisor = EntryAdvisor(
        apiKey: 'k',
        client: MockClient(
          (_) async => _reply(<String, Object?>{
            'descriptions': <String>['저녁식사'],
          }),
        ),
      );

      final hint = await advisor.suggest(
        categories: const <String>[],
        vendor: '더좋은밥상',
        spendTime: '19:24',
      );

      expect(hint!.descriptions, <String>['저녁식사']);
    });

    test('빈 값·중복을 버리고 셋까지만 — 칸에 들어갈 값이라 더 엄하다', () async {
      final advisor = EntryAdvisor(
        apiKey: 'k',
        client: MockClient(
          (_) async => _reply(<String, Object?>{
            'descriptions': <String>[
              ' 저녁식사 ',
              '',
              '저녁식사',
              '회식',
              '식사',
              '팀 저녁',
            ],
          }),
        ),
      );

      final hint = await advisor.suggest(
        categories: const <String>[],
        vendor: '더좋은밥상',
      );

      expect(hint!.descriptions, <String>['저녁식사', '회식', '식사']);
    });

    test('인쇄된 품목이 있으면 내역은 묻지 않는다 — 인쇄된 값이 사실이다', () async {
      Map<String, dynamic>? sent;
      final advisor = EntryAdvisor(
        apiKey: 'k',
        client: MockClient((req) async {
          sent = jsonDecode(req.body) as Map<String, dynamic>;
          return _reply(<String, Object?>{
            'categories': <String>['소모품비'],
            'category_reason': '멀티탭은 사무실 비품이다.',
          });
        }),
      );

      await advisor.suggest(
        categories: _master,
        needDescription: false,
        vendor: '다이소',
        printedDescription: '멀티탭 3구 1.5M',
      );

      final schema =
          ((sent!['output_config'] as Map)['format'] as Map)['schema']
              as Map<String, dynamic>;
      expect((schema['properties'] as Map).containsKey('descriptions'), isFalse);
    });
  });

  group('아예 묻지 않는 경우 — 호출이 일어나면 실패한다', () {
    EntryAdvisor neverCalled() => EntryAdvisor(
      apiKey: 'k',
      client: MockClient((_) async => fail('물을 것이 없는데 호출했다')),
    );

    test('마스터를 못 읽었으면 묻지 않는다 — 고를 목록 없이는 쓸 수 없는 답이 온다', () async {
      expect(
        await neverCalled().suggest(
          categories: const <String>[],
          // 비목만 묻는 호출이고 마스터가 없다 — 고를 목록 없이는
          // 쓸 수 없는 답이 온다.
          needDescription: false,
          printedDescription: '멀티탭 3구',
        ),
        isNull,
      );
    });

    test('업체명도 내역도 없으면 묻지 않는다 — 금액 하나로는 짐작할 재료가 없다', () async {
      expect(
        await neverCalled().suggest(
          categories: _master,
          totalAmount: 9900,
          spendTime: '19:24',
        ),
        isNull,
      );
    });

    test('비목·내역 둘 다 이미 아는 건은 물을 것이 없다', () async {
      expect(
        await neverCalled().suggest(
          categories: _master,
          needCategory: false,
          needDescription: false,
          vendor: '더좋은밥상',
          printedDescription: '된장찌개 2',
        ),
        isNull,
      );
    });
  });
}
