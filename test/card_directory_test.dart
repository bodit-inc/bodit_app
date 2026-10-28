/// 카드보유내역 파싱과, 그걸로 분류를 정하는 판단.
///
/// **우리가 관리하지 않는 시트**를 읽는 코드라 여기를 두껍게 덮는다 —
/// 저쪽이 표기를 바꾸면 분류가 통째로 틀리는데, 그건 돈이 틀린 예산에
/// 잡힌다는 뜻이고 시트는 append-only 라 앱으로 못 되돌린다.
library;

import 'package:bodit_app/data/remote/card_repository.dart';
import 'package:bodit_app/features/review/review_controller.dart';
import 'package:bodit_app/models/entry_draft.dart';
import 'package:flutter_test/flutter_test.dart';

/// `A no. · B 은행 · C 카드번호 · D 분류코드 · E 분류명 · F 구분 · G 현재사용여부`
List<Object?> row(
  String number,
  Object code, {
  String active = 'O',
  String name = '',
  String scope = '사업비',
}) => <Object?>['1', '신한', number, code, name, scope, active];

/// 실제 시트에서 그대로 가져온 표기.
const _masked = '5531-46**-****-3927';

void main() {
  group('뒤 4자리 뽑기', () {
    test('시트의 마스킹 표기에서 뽑는다', () {
      expect(CardDirectory.last4Of(_masked), '3927');
    });

    test('구분자가 바뀌어도 뽑는다 — 저쪽 시트라 표기를 못 고정한다', () {
      expect(CardDirectory.last4Of('5531 46** **** 9832'), '9832');
      expect(CardDirectory.last4Of('5531·46**·****·7669'), '7669');
      expect(CardDirectory.last4Of('5531460000005982'), '5982');
    });

    test('사용자가 네 자리만 쳐도 같은 규칙으로 걸린다', () {
      expect(CardDirectory.last4Of('3927'), '3927');
      expect(CardDirectory.last4Of(' 3927 '), '3927');
    });

    test('숫자가 모자라면 못 뽑는다 — 억지로 맞추지 않는다', () {
      expect(CardDirectory.last4Of(''), isNull);
      expect(CardDirectory.last4Of('392'), isNull);
      expect(CardDirectory.last4Of('카드없음'), isNull);
    });
  });

  group('현재사용여부', () {
    test('O 만 사용 중이다', () {
      final d = CardDirectory.fromRows([
        row(_masked, 3),
        row('5531-46**-****-9832', 3, active: 'X'),
      ]);
      expect(d.findActive('3927'), hasLength(1));
      expect(d.findActive('9832'), isEmpty);
    });

    test('미사용 카드도 목록에는 남는다', () {
      // 버리면 "못 찾았다" 와 "지금은 안 쓰는 카드다" 를 구분해줄 수 없다.
      // 몇 달 지난 영수증을 뒤늦게 올리는 일은 흔하다.
      final d = CardDirectory.fromRows([row(_masked, 3, active: 'X')]);
      expect(d.find('3927'), hasLength(1));
      expect(d.find('3927').single.active, isFalse);
    });

    test('사람이 손으로 적는 칸이라 소문자·공백은 받아준다', () {
      final d = CardDirectory.fromRows([
        row(_masked, 3, active: ' o '),
        row('5531-46**-****-9832', 3, active: 'O '),
      ]);
      expect(d.findActive('3927'), hasLength(1));
      expect(d.findActive('9832'), hasLength(1));
    });

    test('빈칸은 미사용이다 — 비어 있는 걸 사용 중으로 보면 안 된다', () {
      final d = CardDirectory.fromRows([row(_masked, 3, active: '')]);
      expect(d.findActive('3927'), isEmpty);
    });
  });

  group('쓸 수 없는 행', () {
    test('분류코드가 없으면 버린다 — 그 카드로는 분류를 못 정한다', () {
      final d = CardDirectory.fromRows([row(_masked, '')]);
      expect(d.find('3927'), isEmpty);
    });

    test('분류코드가 숫자가 아니면 버린다', () {
      final d = CardDirectory.fromRows([row(_masked, '법인')]);
      expect(d.find('3927'), isEmpty);
    });

    test('카드번호가 없으면 버린다', () {
      final d = CardDirectory.fromRows([row('', 3)]);
      expect(d.cardCount, 0);
    });

    test('컬럼이 모자란 행에서 터지지 않는다', () {
      final d = CardDirectory.fromRows(const [
        <Object?>['1', '신한', _masked],
      ]);
      expect(d.cardCount, 0);
    });
  });

  group('뒤 4자리는 열쇠가 아니다', () {
    test('겹치면 둘 다 돌려준다', () {
      // 지금은 21장이 전부 다르지만 카드가 늘면 언제든 겹친다.
      final d = CardDirectory.fromRows([
        row(_masked, 3),
        row('9410-19**-****-3927', 24),
      ]);
      expect(d.findActive('3927'), hasLength(2));
    });
  });

  group('분류명은 마스터에서만 푼다', () {
    // 카드 시트에도 분류명 칸이 있지만 안 읽는다. 실제로 두 시트가 어긋난
    // 적이 있다 — 카드 시트 44 = 글로벌팁스(카드), 마스터 44 = 딥테크(카드).
    const master = {3: '법인(신용)', 44: '글로벌팁스(카드)'};

    test('카드 시트에 적힌 이름이 아니라 마스터 이름을 쓴다', () {
      final card = CardDirectory.fromRows([row(_masked, 44, name: '딥테크(카드)')])
          .find('3927')
          .single;
      expect(resolveClass(card, master)?.name, '글로벌팁스(카드)');
    });

    test('마스터에 없는 코드는 null — 이름 없이 코드만 넣지 않는다', () {
      final card = CardDirectory.fromRows([row(_masked, 99)])
          .find('3927')
          .single;
      expect(resolveClass(card, master), isNull);
    });
  });

  group('카드로 분류 정하기', () {
    const master = {3: '법인(신용)', 24: 'CTS(체크)', 44: '글로벌팁스(카드)'};
    final cards = CardDirectory.fromRows([
      row(_masked, 3, scope: '법인'),
      row('9410-19**-****-3356', 24),
      row('5525-76**-****-6302', 44),
      row('5525-76**-****-9964', 44, active: 'X'),
      // 뒤 4자리가 겹치는 두 장
      row('5531-46**-****-1111', 3, scope: '법인'),
      row('9410-19**-****-1111', 24),
      // 마스터에 없는 코드
      row('4373-68**-****-2222', 99),
    ]);

    EntryDraft draftWith(String? last4) =>
        EntryDraft(evidencePath: '/tmp/x.jpg', cardLast4: last4);

    test('한 장이면 분류를 채우고 근거를 남긴다', () {
      final d = ReviewController.applyCardClass(
        draftWith('3356'),
        cards,
        master,
      );
      expect(d.classCode, 24);
      expect(d.className, 'CTS(체크)');
      expect(d.classReason, contains('3356'));
      expect(d.cardNotice, isNull);
    });

    test('카드가 없는 증빙이면 아무 말도 하지 않는다', () {
      // 이체·현금 건마다 경고가 뜨면 배너를 아무도 안 읽게 된다.
      for (final v in <String?>[null, '', '   ']) {
        final d = ReviewController.applyCardClass(draftWith(v), cards, master);
        expect(d.classCode, isNull);
        expect(d.cardNotice, isNull, reason: 'cardLast4=$v');
      }
    });

    test('못 찾으면 분류를 비우고 왜 비었는지 말한다', () {
      final d = ReviewController.applyCardClass(
        draftWith('0000'),
        cards,
        master,
      );
      expect(d.classCode, isNull);
      expect(d.cardNotice, contains('찾지 못했습니다'));
    });

    test('미사용 카드는 "못 찾았다" 와 다른 문구로 알린다', () {
      final d = ReviewController.applyCardClass(
        draftWith('9964'),
        cards,
        master,
      );
      expect(d.classCode, isNull);
      expect(d.cardNotice, contains('사용하지 않는'));
    });

    test('겹치면 자동으로 안 고르고 후보를 준다', () {
      final d = ReviewController.applyCardClass(
        draftWith('1111'),
        cards,
        master,
      );
      expect(d.classCode, isNull, reason: '조용히 첫 번째를 고르면 절반이 틀린다');
      expect(d.classSuggestions.map((c) => c.code), [3, 24]);
      expect(d.cardNotice, contains('2장'));
    });

    test('마스터에 없는 코드면 멈추고 마스터를 짚어준다', () {
      final d = ReviewController.applyCardClass(
        draftWith('2222'),
        cards,
        master,
      );
      expect(d.classCode, isNull);
      expect(d.cardNotice, contains('99'));
      expect(d.cardNotice, contains('_분류마스터'));
    });

    test('사용자가 직접 고른 분류는 카드가 바뀌어도 안 지운다', () {
      // 46개 목록에서 고르면 classReason 이 없다 — 그게 "내가 골랐다" 는 표시다.
      final picked = draftWith('3356')
          .copyWith(classCode: 32, className: '수출바우처');
      final after = ReviewController.applyCardClass(
        picked.copyWith(cardLast4: '0000'),
        cards,
        master,
      );
      expect(after.classCode, 32);
      expect(after.className, '수출바우처');
    });

    test('시트를 못 읽었으면 그 사실을 알린다 — 조용히 비우지 않는다', () {
      final d = ReviewController.applyCardClass(draftWith('3356'), null, null);
      expect(d.classCode, isNull);
      expect(d.cardNotice, isNotNull);
    });

    test('다시 판단하면 지난 흔적이 남지 않는다', () {
      // 카드번호를 고쳤는데 예전 근거가 남아 있으면 사용자는 반영된 줄 안다.
      final first = ReviewController.applyCardClass(
        draftWith('3356'),
        cards,
        master,
      );
      final second = ReviewController.applyCardClass(
        first.copyWith(cardLast4: '0000'),
        cards,
        master,
      );
      expect(second.classReason, isNull);
      expect(second.classSuggestions, isEmpty);
      expect(second.cardNotice, contains('찾지 못했습니다'));
      // 카드가 채운 값이었으니 카드가 바뀌면 같이 내려가야 한다.
      // 남겨두면 3356 의 분류가 0000 짜리 건에 조용히 붙는다.
      expect(second.classCode, isNull);
    });
  });

  group('자리별로 대조하기', () {
    test('가려진 자리를 null 로, 아는 자리는 그대로 뽑는다', () {
      expect(CardDirectory.slotsOf('766*'), <String?>['7', '6', '6', null]);
      expect(CardDirectory.slotsOf('*669'), <String?>[null, '6', '6', '9']);
      expect(CardDirectory.slotsOf('76*9'), <String?>['7', '6', null, '9']);
      expect(CardDirectory.slotsOf('7***'), <String?>['7', null, null, null]);
    });

    test('마스크 문자 종류를 가리지 않는다', () {
      // `*` 만 받으면 목록에서 빠진 문자가 나오는 순간 또 조회가 안 된다.
      for (final mask in <String>['*', 'x', 'X', '#', '●', '?']) {
        expect(CardDirectory.slotsOf('766$mask'), <String?>[
          '7',
          '6',
          '6',
          null,
        ], reason: '마스크 "$mask" 를 못 받았다');
      }
    });

    test('구분자는 지우고 자리를 맞춘다', () {
      // `-` 와 `*` 는 둘 다 숫자가 아니지만 하나는 구분자다.
      expect(CardDirectory.slotsOf('5531-46**-****-766*'), <String?>[
        '7',
        '6',
        '6',
        null,
      ]);
      expect(CardDirectory.slotsOf('5531 46** **** 76*9'), <String?>[
        '7',
        '6',
        null,
        '9',
      ]);
    });

    test('네 자리를 못 채우면 추측하지 않는다', () {
      // `66*` 가 `?66*` 인지 `66*?` 인지 알 수 없다. 한쪽으로 가정하면
      // 틀린 카드를 고르고 분류가 통째로 틀린다.
      expect(CardDirectory.slotsOf('66*'), isNull);
      expect(CardDirectory.slotsOf('*'), isNull);
      expect(CardDirectory.slotsOf(''), isNull);
    });

    test('아는 자리가 하나도 없으면 조회 대상이 아니다', () {
      final allMasked = CardDirectory.slotsOf('****')!;
      expect(CardDirectory.hasAnyDigit(allMasked), isFalse);
      // 네 글자지만 숫자가 없다 — 전부 와일드카드면 모든 카드가 걸린다.
      final korean = CardDirectory.slotsOf('카드없음')!;
      expect(CardDirectory.hasAnyDigit(korean), isFalse);
    });

    test('전부 숫자면 완전일치다', () {
      final slots = CardDirectory.slotsOf('3927')!;
      expect(CardDirectory.isExact(slots), isTrue);
      expect(CardDirectory.hasAnyDigit(slots), isTrue);
      expect(CardDirectory.isExact(CardDirectory.slotsOf('392*')!), isFalse);
    });

    test('표기를 하나로 모은다', () {
      // 같은 카드가 영수증마다 다른 문자로 시트에 들어가면 안 된다.
      expect(CardDirectory.patternOf(CardDirectory.slotsOf('766x')!), '766*');
      expect(CardDirectory.patternOf(CardDirectory.slotsOf('766#')!), '766*');
      expect(CardDirectory.patternOf(CardDirectory.slotsOf('3927')!), '3927');
    });

    test('후보를 활성 먼저, 번호순으로 돌려준다', () {
      // 문구가 호출마다 뒤바뀌면 사용자가 다른 결과로 읽는다.
      final cards = CardDirectory.fromRows(<List<Object?>>[
        row('5525-76**-****-7663', 44),
        row('5525-76**-****-7662', 44, active: 'X'),
        row('5525-76**-****-7661', 44),
        row('9410-19**-****-3356', 24),
      ]);
      final hits = cards.findByPattern(CardDirectory.slotsOf('766*')!);
      expect(hits.map((c) => c.last4), <String>['7661', '7663', '7662']);
      expect(hits.last.active, isFalse);
    });

    test('아는 자리가 하나면 그 자리만 맞는 카드가 다 걸린다', () {
      final cards = CardDirectory.fromRows(<List<Object?>>[
        row('5525-76**-****-7001', 44),
        row('5525-76**-****-7999', 44),
        row('9410-19**-****-3356', 24),
      ]);
      final hits = cards.findByPattern(CardDirectory.slotsOf('7***')!);
      expect(hits.length, 2);
      expect(hits.every((c) => c.last4.startsWith('7')), isTrue);
    });
  });

  group('가려진 자리로 분류 정하기', () {
    const master = {3: '법인(신용)', 24: 'CTS(체크)', 44: '글로벌팁스(카드)'};

    EntryDraft draftWith(String? last4) =>
        EntryDraft(evidencePath: '/tmp/x.jpg', cardLast4: last4);

    test('후보가 한 장이면 실제 뒤 4자리로 바꿔 넣는다', () {
      // 패턴이 그대로 시트에 들어가면 회계 담당자가 카드를 특정할 수 없다.
      final cards = CardDirectory.fromRows(<List<Object?>>[
        row('5525-76**-****-7662', 44),
        row('9410-19**-****-3356', 24),
      ]);
      final d = ReviewController.applyCardClass(
        draftWith('766*'),
        cards,
        master,
      );
      expect(d.cardLast4, '7662');
      expect(d.classCode, 44);
      // 추측이 섞였다는 것이 보여야 한다.
      expect(d.classReason, contains('766*'));
      expect(d.classReason, contains('추정'));
      expect(d.cardNotice, isNull);
    });

    test('후보가 여럿이어도 분류가 같으면 묻지 않는다', () {
      // 카드 시트를 읽는 이유는 분류 하나다. 답이 정해졌으면 물을 게 없다.
      final cards = CardDirectory.fromRows(<List<Object?>>[
        row('5525-76**-****-7662', 44),
        row('5525-76**-****-7663', 44),
      ]);
      final d = ReviewController.applyCardClass(
        draftWith('766*'),
        cards,
        master,
      );
      expect(d.classCode, 44);
      expect(d.cardNotice, isNull);
      // 어느 카드인지는 모르므로 번호는 패턴을 그대로 남긴다.
      expect(d.cardLast4, '766*');
      expect(d.classReason, contains('후보 2장'));
    });

    test('분류가 갈리면 후보 카드를 보여주고 고르게 한다', () {
      final cards = CardDirectory.fromRows(<List<Object?>>[
        row('5525-76**-****-7662', 44),
        row('9410-76**-****-7663', 24),
      ]);
      final d = ReviewController.applyCardClass(
        draftWith('766*'),
        cards,
        master,
      );
      expect(d.classCode, isNull);
      expect(d.classSuggestions.length, 2);
      expect(d.cardNotice, contains('766*'));
      expect(d.cardNotice, contains('7662'));
      expect(d.cardNotice, contains('7663'));
      expect(d.cardNotice, contains('직접 선택'));
    });

    test('후보가 많으면 셋까지만 적는다', () {
      // 다 적으면 배너가 화면을 덮고 아무도 읽지 않는다.
      const wide = {40: '가', 41: '나', 42: '다', 43: '라', 44: '글로벌팁스(카드)'};
      final cards = CardDirectory.fromRows(<List<Object?>>[
        for (var i = 0; i < 5; i++) row('5525-76**-****-700$i', 40 + i),
      ]);
      final d = ReviewController.applyCardClass(draftWith('7***'), cards, wide);
      // 분류가 다섯으로 갈렸으니 골라야 한다. 카드 이름은 셋까지.
      expect(d.classCode, isNull);
      expect(d.cardNotice, contains('외 2장'));
    });

    test('분류 마스터에 없는 코드면 패턴도 문구에 그대로 쓴다', () {
      final cards = CardDirectory.fromRows(<List<Object?>>[
        row('5525-76**-****-7662', 99),
      ]);
      final d = ReviewController.applyCardClass(
        draftWith('766*'),
        cards,
        master,
      );
      // "해당되는 카드 의 분류코드" 처럼 조사가 떠버리지 않아야 한다.
      expect(d.cardNotice, contains('766* 에 해당되는 카드의 분류코드 99'));
    });

    test('가려진 자리로도 못 찾으면 그렇게 말한다', () {
      final cards = CardDirectory.fromRows(<List<Object?>>[
        row('9410-19**-****-3356', 24),
      ]);
      final d = ReviewController.applyCardClass(
        draftWith('766*'),
        cards,
        master,
      );
      expect(d.cardNotice, contains('766*'));
      expect(d.cardNotice, contains('찾지 못했습니다'));
    });

    test('미사용 카드만 걸리면 "없다" 가 아니라 "안 쓴다" 고 말한다', () {
      // 사용자가 할 일이 다르다 — 번호를 고칠 일인지, 그냥 고르면 되는지.
      final cards = CardDirectory.fromRows(<List<Object?>>[
        row('5525-76**-****-7662', 44, active: 'X'),
      ]);
      final d = ReviewController.applyCardClass(
        draftWith('766*'),
        cards,
        master,
      );
      expect(d.cardNotice, contains('사용하지 않는'));
    });

    test('네 자리를 못 채우거나 아는 자리가 없으면 멈춘다', () {
      final cards = CardDirectory.fromRows(<List<Object?>>[
        row('5525-76**-****-7662', 44),
      ]);
      for (final raw in <String>['66*', '****', '카드없음']) {
        final d = ReviewController.applyCardClass(
          draftWith(raw),
          cards,
          master,
        );
        expect(d.classCode, isNull, reason: raw);
        expect(d.cardNotice, contains('읽지 못했습니다'), reason: raw);
      }
    });

    test('완전일치는 문구가 예전과 같다', () {
      // 가려진 자리가 없는 흔한 경우의 말투를 바꾸지 않았다.
      final cards = CardDirectory.fromRows(<List<Object?>>[
        row('9410-19**-****-3356', 24),
      ]);
      final d = ReviewController.applyCardClass(
        draftWith('3356'),
        cards,
        master,
      );
      expect(d.classReason, '카드 3356 · CTS(체크)');
      expect(d.classReason, isNot(contains('추정')));
    });
  });

  group('카드가 정한 분류를 기억한다', () {
    const master = {3: '법인(신용)', 24: 'CTS(체크)', 44: '글로벌팁스(카드)'};

    EntryDraft draftWith(String? last4) =>
        EntryDraft(evidencePath: '/tmp/x.jpg', cardLast4: last4);

    test('확정하면 cardClass 에 코드와 이름을 같이 남긴다', () {
      // 나중에 사용자가 다른 분류로 고쳤는지 비교하려면 원래 값이 있어야 한다.
      final cards = CardDirectory.fromRows(<List<Object?>>[
        row('9410-19**-****-3356', 24),
      ]);
      final d = ReviewController.applyCardClass(
        draftWith('3356'),
        cards,
        master,
      );
      expect(d.cardClass?.code, 24);
      expect(d.cardClass?.name, 'CTS(체크)');
      expect(d.classDiffersFromCard, isFalse);
    });

    test('카드번호를 고치면 카드가 정했던 분류도 내려간다', () {
      // 남겨두면 예전 카드의 분류와 비교해서 엉뚱한 경고가 뜬다.
      final cards = CardDirectory.fromRows(<List<Object?>>[
        row('9410-19**-****-3356', 24),
      ]);
      final first = ReviewController.applyCardClass(
        draftWith('3356'),
        cards,
        master,
      );
      final second = ReviewController.applyCardClass(
        first.copyWith(cardLast4: '0000'),
        cards,
        master,
      );
      expect(second.cardClass, isNull);
      expect(second.classDiffersFromCard, isFalse);
    });

    test('사용자가 다른 분류로 고치면 카드와 다르다고 본다', () {
      final cards = CardDirectory.fromRows(<List<Object?>>[
        row('9410-19**-****-3356', 24),
      ]);
      final d = ReviewController.applyCardClass(
        draftWith('3356'),
        cards,
        master,
      );
      // picker 에서 직접 고른 상태를 흉내낸다 — classCode 만 바뀐다.
      expect(d.copyWith(classCode: 3).classDiffersFromCard, isTrue);
    });
  });
}
