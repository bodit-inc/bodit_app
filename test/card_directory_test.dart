/// 카드보유내역 파싱과, 그걸로 분류를 정하는 판단.
///
/// **우리가 관리하지 않는 시트**를 읽는 코드라 여기를 두껍게 덮는다 —
/// 저쪽이 표기를 바꾸면 분류가 통째로 틀리는데, 그건 돈이 틀린 예산에
/// 잡힌다는 뜻이고 시트는 append-only 라 앱으로 못 되돌린다.
library;

import 'package:bodit_app/data/remote/card_repository.dart';
import 'package:bodit_app/data/remote/sheets_repository.dart';
import 'package:bodit_app/features/review/review_controller.dart';
import 'package:bodit_app/models/entry_draft.dart';
import 'package:bodit_app/models/ocr_original.dart';
import 'package:flutter_test/flutter_test.dart';

/// `A no. · B 은행 · C 카드번호 · D 분류코드 · E 분류명 · F 구분 · G 현재사용여부`
List<Object?> row(
  String number,
  Object code, {
  String active = 'O',
  String name = '',
  String scope = '사업비',
}) => <Object?>['1', '신한', number, code, name, scope, active];

/// 매입내역 한 행. 색인이 읽는 범위와 같은 모양이다 —
/// `H 분류코드 · I 분류명 · J 카드번호`. **I열은 색인이 쓰지 않는다**(일부러
/// 틀린 이름을 넣어서, 그걸 읽으면 테스트가 깨지게 둔다).
List<Object?> past(Object code, String card) => <Object?>[
  code,
  '읽지 않는 이름',
  card,
];

/// 실제 시트에서 그대로 가져온 표기.
const _masked = '5531-46**-****-3927';

void main() {
  group('번호 표기 모으기', () {
    test('시트의 마스킹 표기는 그대로 들고 있는다', () {
      // 이미 우리 규칙과 같은 모양이다. 자리를 버리지 않는다 —
      // 앞자리가 뒤 4자리 겹침을 가르는 근거다.
      expect(CardDirectory.normalized(_masked), _masked);
    });

    test('구분자·마스크 문자가 달라도 한 모양으로 모은다', () {
      // 저쪽 시트라 표기를 못 고정하고, 영수증도 인쇄가 제각각이다.
      // 같은 카드가 두 모양으로 시트에 들어가면 사람이 다른 카드로 읽는다.
      expect(CardDirectory.normalized('5531 46** **** 9832'), '5531-46**-****-9832');
      expect(CardDirectory.normalized('5531·46xx·xxxx·7669'), '5531-46**-****-7669');
      expect(CardDirectory.normalized('5531460000005982'), '5531-4600-0000-5982');
    });

    test('뒤 4자리만 찍힌 영수증도 그대로 받는다', () {
      // 대조는 뒤에서 맞추므로 짧아도 걸린다.
      expect(CardDirectory.normalized('3927'), '3927');
      expect(CardDirectory.normalized(' 3927 '), '3927');
    });

    test('4로 안 나눠지는 자리 수는 남는 것을 끝에 붙인다', () {
      // 15자리(Amex)는 카드사 인쇄가 4-6-5 지만, 자리 수마다 규칙을 두면
      // 같은 카드가 두 모양이 된다. 규칙 하나로 모은다.
      expect(CardDirectory.normalized('378282246310005'), '3782-8224-6310-005');
    });

    test('쓸 수 없는 값은 null — 억지로 맞추지 않는다', () {
      expect(CardDirectory.normalized(null), isNull);
      expect(CardDirectory.normalized(''), isNull);
      expect(CardDirectory.normalized('392'), isNull);
      // 네 자리지만 아는 자리가 없다 — 모든 카드가 걸린다.
      expect(CardDirectory.normalized('****'), isNull);
      expect(CardDirectory.normalized('카드없음'), isNull);
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

  group('뒤 4자리만으로는 갈리지 않는다', () {
    test('뒤 4자리로 조회하면 겹치는 두 장이 다 걸린다', () {
      final d = CardDirectory.fromRows([
        row(_masked, 3),
        row('9410-19**-****-3927', 24),
      ]);
      expect(d.findActive('3927'), hasLength(2));
    });

    test('번호 전체로 조회하면 앞자리가 갈라준다', () {
      // **이게 전체 번호를 읽는 이유다.** 앞자리는 영수증에 인쇄돼 있었는데
      // 예전엔 버렸고, 그래서 사용자에게 어느 카드인지 되물었다.
      final d = CardDirectory.fromRows([
        row(_masked, 3),
        row('9410-19**-****-3927', 24),
      ]);
      expect(d.findActive(_masked), hasLength(1));
      expect(d.findActive(_masked).single.classCode, 3);
      expect(d.findActive('9410-19**-****-3927').single.classCode, 24);
    });

    test('가려진 자리는 어긋남이 아니다 — 양쪽이 다른 자리를 가린다', () {
      final d = CardDirectory.fromRows([row(_masked, 3)]);
      // 영수증이 앞자리만 보여주고 뒤를 가린 경우다. 아는 자리로 걸린다 —
      // 가려진 자리는 "어긋났다" 고 말할 근거가 없다.
      expect(d.findActive('5531-46**-****-****'), hasLength(1));
      expect(d.findActive('5531-46**-****-39**'), hasLength(1));
      // 아는 자리가 어긋나면 다른 카드다.
      expect(d.findActive('9410-19**-****-3927'), isEmpty);
      // 전부 가려졌으면 조회 자체를 하지 않는다 — 모든 카드가 걸린다.
      expect(d.findActive('****-****-****-****'), isEmpty);
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

    EntryDraft draftWith(String? number) =>
        EntryDraft(evidencePath: '/tmp/x.jpg', cardNumber: number);

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

    test('카드가 없는 증빙이면 기본값을 넣고 배너는 안 띄운다', () {
      // 이체·현금 건마다 경고가 뜨면 배너를 아무도 안 읽게 된다. 그런데
      // 분류를 비워두면 그 건은 **전부** 사용자가 목록에서 골라야 했다.
      for (final v in <String?>[null, '', '   ']) {
        final d = ReviewController.applyCardClass(draftWith(v), cards, master);
        expect(d.classCode, ReviewController.defaultClassCode, reason: '$v');
        expect(d.className, '법인(신용)', reason: 'cardNumber=$v');
        expect(d.cardNotice, isNull, reason: 'cardNumber=$v');
        // 기본값이라는 것은 조용한 한 줄로 말한다.
        expect(d.classReason, contains('기본값'), reason: 'cardNumber=$v');
        // **카드가 정한 사실이 아니다.** 여기에 넣으면 사용자가 다른 분류로
        // 고칠 때 "카드가 정한 분류와 다르다" 경고가 뜬다.
        expect(d.cardClass, isNull, reason: 'cardNumber=$v');
      }
    });

    test('못 찾으면 기본값을 넣고 왜 못 찾았는지 말한다', () {
      final d = ReviewController.applyCardClass(
        draftWith('0000'),
        cards,
        master,
      );
      expect(d.classCode, ReviewController.defaultClassCode);
      expect(d.cardNotice, contains('찾지 못했습니다'));
      // 값이 채워진 채로 "직접 골라주세요" 로 끝나면 할 일을 알 수 없다.
      expect(d.cardNotice, contains('기본값'));
    });

    test('미사용 카드는 "못 찾았다" 와 다른 문구로 알린다', () {
      final d = ReviewController.applyCardClass(
        draftWith('9964'),
        cards,
        master,
      );
      // 카드 시트에 44 가 적혀 있지만 그걸 쓰지 않는다 — 낡은 행일 수 있어서
      // 사용자가 확인해야 하는 신호다. 분류는 기본값으로 둔다.
      expect(d.classCode, ReviewController.defaultClassCode);
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
      // **기본값도 넣지 않는다.** 고를 후보가 떠 있는데 값이 채워져 있으면
      // 사용자가 후보를 안 보고 지나간다.
      expect(d.classReason, isNull);
    });

    test('마스터에 없는 코드면 멈추고 마스터를 짚어준다', () {
      final d = ReviewController.applyCardClass(
        draftWith('2222'),
        cards,
        master,
      );
      // **기본값을 넣지 않는다.** 카드는 99 라고 말했는데 기본값 3 을 넣으면
      // 카드가 말한 것과 다른 분류를 조용히 적는 셈이다.
      expect(d.classCode, isNull);
      expect(d.cardNotice, contains('99'));
      expect(d.cardNotice, contains('_분류마스터'));
    });

    test('사용자가 직접 고른 분류는 카드가 바뀌어도 안 지운다', () {
      // 46개 목록에서 고르면 classReason 이 없다 — 그게 "내가 골랐다" 는 표시다.
      final picked = draftWith('3356')
          .copyWith(classCode: 32, className: '수출바우처');
      final after = ReviewController.applyCardClass(
        picked.copyWith(cardNumber: '0000'),
        cards,
        master,
      );
      expect(after.classCode, 32);
      expect(after.className, '수출바우처');
    });

    test('시트를 못 읽었으면 그 사실을 알리고 기본값을 넣는다', () {
      final d = ReviewController.applyCardClass(draftWith('3356'), null, null);
      expect(d.cardNotice, isNotNull);
      // 마스터를 못 읽은 경우가 하필 picker 도 못 여는 경우다. 그때 기본값까지
      // 포기하면 제출할 길이 없어서, 이름 하나는 코드에 둔다.
      expect(d.classCode, ReviewController.defaultClassCode);
      expect(d.className, ReviewController.defaultClassName);
    });

    test('다시 판단하면 지난 흔적이 남지 않는다', () {
      // 카드번호를 고쳤는데 예전 근거가 남아 있으면 사용자는 반영된 줄 안다.
      final first = ReviewController.applyCardClass(
        draftWith('3356'),
        cards,
        master,
      );
      final second = ReviewController.applyCardClass(
        first.copyWith(cardNumber: '0000'),
        cards,
        master,
      );
      expect(second.classSuggestions, isEmpty);
      expect(second.cardNotice, contains('찾지 못했습니다'));
      // 카드가 채운 값이었으니 카드가 바뀌면 같이 내려가야 한다.
      // 남겨두면 3356 의 분류가 0000 짜리 건에 조용히 붙는다.
      expect(second.classCode, isNot(24));
      expect(second.className, isNot('CTS(체크)'));
      // 지난 근거도 남지 않는다 — 새 번호로 다시 판단한 결과만 보인다.
      expect(second.classReason, isNot(contains('3356')));
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

    test('구분자는 지우고 자리를 맞춘다 — 자리를 자르지 않는다', () {
      // `-` 와 `*` 는 둘 다 숫자가 아니지만 하나는 구분자다.
      // **앞자리를 버리지 않는다** — 대조의 근거가 거기 있다.
      expect(CardDirectory.slotsOf('5531-46**-****-766*'), <String?>[
        '5', '5', '3', '1',
        '4', '6', null, null,
        null, null, null, null,
        '7', '6', '6', null,
      ]);
      expect(CardDirectory.slotsOf('5531 46** **** 76*9')?.length, 16);
    });

    test('네 자리를 못 채우면 추측하지 않는다', () {
      // 대조는 뒤에서 맞추므로 `66*` 는 "뒤 세 자리" 로 읽히는데, 뒤 세
      // 자리만 맞는 카드는 여러 장이고 그중 하나를 고르면 분류가 통째로
      // 틀린다. 시트는 append-only 라 되돌릴 수 없다.
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

    test('가려진 자리가 하나도 없으면 완전일치다', () {
      final slots = CardDirectory.slotsOf('3927')!;
      expect(CardDirectory.isExact(slots), isTrue);
      expect(CardDirectory.hasAnyDigit(slots), isTrue);
      expect(CardDirectory.isExact(CardDirectory.slotsOf('392*')!), isFalse);
      // 카드 영수증은 대개 가려서 인쇄한다 — 전체 번호는 완전일치가 아니다.
      expect(CardDirectory.isExact(CardDirectory.slotsOf(_masked)!), isFalse);
    });

    test('표기를 하나로 모으고 4자리마다 끊는다', () {
      // 같은 카드가 영수증마다 다른 문자로 시트에 들어가면 안 된다.
      expect(CardDirectory.patternOf(CardDirectory.slotsOf('766x')!), '766*');
      expect(CardDirectory.patternOf(CardDirectory.slotsOf('766#')!), '766*');
      expect(CardDirectory.patternOf(CardDirectory.slotsOf('3927')!), '3927');
      expect(
        CardDirectory.patternOf(CardDirectory.slotsOf('5531 46xx xxxx 3927')!),
        _masked,
      );
    });

    test('아는 자리를 겹쳐 모은다 — 양쪽이 다른 자리를 가린다', () {
      // 영수증은 `766*`, 카드 시트는 `5525-76**-****-7662` 를 안다.
      // 한쪽만 적으면 아는 것을 버린다.
      final merged = CardDirectory.merge(
        CardDirectory.slotsOf('766*')!,
        CardDirectory.slotsOf('5525-76**-****-7662')!,
      );
      expect(CardDirectory.patternOf(merged), '5525-76**-****-7662');
      // 뒤에서 맞춘다 — 짧은 쪽의 자리가 뒤로 간다.
      final tail = CardDirectory.merge(
        CardDirectory.slotsOf('1234')!,
        CardDirectory.slotsOf('5525-76**-****-****')!,
      );
      expect(CardDirectory.patternOf(tail), '5525-76**-****-1234');
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
      expect(hits.map((c) => c.number), <String>[
        '5525-76**-****-7661',
        '5525-76**-****-7663',
        '5525-76**-****-7662',
      ]);
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
      // 조회값이 네 자리라 **뒤 네 자리**와 대조된다.
      expect(
        hits.every((c) => c.number.split('-').last.startsWith('7')),
        isTrue,
      );
    });
  });

  group('가려진 자리로 분류 정하기', () {
    const master = {3: '법인(신용)', 24: 'CTS(체크)', 44: '글로벌팁스(카드)'};

    EntryDraft draftWith(String? number) =>
        EntryDraft(evidencePath: '/tmp/x.jpg', cardNumber: number);

    test('후보가 한 장이면 카드 시트가 아는 자리를 겹쳐 넣는다', () {
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
      expect(d.cardNumber, '5525-76**-****-7662');
      expect(d.classCode, 44);
      // 영수증에 없던 자리를 색인으로 메웠으니 추측이 섞였다 — 보여야 한다.
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
      // 어느 카드인지는 모르므로 영수증에서 읽은 것만 남긴다.
      expect(d.cardNumber, '766*');
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
        // 카드로는 못 정했다 — 그래서 기본값이다(카드 분류 44 가 아니다).
        expect(d.classCode, ReviewController.defaultClassCode, reason: raw);
        expect(d.cardNotice, contains('읽지 못했습니다'), reason: raw);
      }
    });

    test('뒤 4자리만 읽은 건은 앞자리를 메웠다고 적는다', () {
      // 영수증에 뒤 4자리만 찍혀 있으면 앞자리는 **우리가 못 본 자리**다.
      // 색인으로 메운 것이므로 그렇게 말한다.
      final cards = CardDirectory.fromRows(<List<Object?>>[
        row('9410-19**-****-3356', 24),
      ]);
      final d = ReviewController.applyCardClass(
        draftWith('3356'),
        cards,
        master,
      );
      expect(d.cardNumber, '9410-19**-****-3356');
      expect(d.classReason, '카드 9410-19**-****-3356 · CTS(체크) (3356 로 추정)');
    });

    test('영수증이 번호를 통째로 찍어줬으면 추정이 아니다', () {
      // **경고는 드물어야 읽힌다.** 카드 시트가 채워준 자리가 없으면
      // (둘이 같은 자리를 가렸다) 확정 매칭과 같은 말투로 둔다.
      final cards = CardDirectory.fromRows(<List<Object?>>[row(_masked, 3)]);
      final d = ReviewController.applyCardClass(
        draftWith(_masked),
        cards,
        master,
      );
      expect(d.cardNumber, _masked);
      expect(d.classReason, '카드 $_masked · 법인(신용)');
      expect(d.classReason, isNot(contains('추정')));
    });
  });

  group('카드가 정한 분류를 기억한다', () {
    const master = {3: '법인(신용)', 24: 'CTS(체크)', 44: '글로벌팁스(카드)'};

    EntryDraft draftWith(String? number) =>
        EntryDraft(evidencePath: '/tmp/x.jpg', cardNumber: number);

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
        first.copyWith(cardNumber: '0000'),
        cards,
        master,
      );
      expect(second.cardClass, isNull);
      expect(second.classDiffersFromCard, isFalse);
    });

    test('앱이 가려진 자리를 좁힌 것은 사용자가 고친 것이 아니다', () {
      // 원본을 그대로 두면 "766* 로 인식했습니다" 가 떠서 앱이 한 일을
      // 사용자 탓으로 돌리고, 되돌리기 칩이 766* 를 다시 넣으려 한다.
      final cards = CardDirectory.fromRows(<List<Object?>>[
        row('5525-76**-****-7662', 44),
      ]);
      final d = ReviewController.applyCardClass(
        draftWith('766*')
            .copyWith(ocrOriginal: const OcrOriginal(cardNumber: '766*')),
        cards,
        master,
      );
      expect(d.cardNumber, '5525-76**-****-7662');
      expect(d.ocrOriginal?.cardNumber, '5525-76**-****-7662');
      expect(d.cardNumberOcrConflict, isNull);
    });

    test('좁히지 못했으면 원본을 건드리지 않는다', () {
      // 분류가 갈려 확정하지 못한 경우다. 앱이 번호를 바꾸지 않았으므로
      // 원본도 그대로여야 한다.
      final cards = CardDirectory.fromRows(<List<Object?>>[
        row('5525-76**-****-7662', 44),
        row('9410-76**-****-7663', 24),
      ]);
      final d = ReviewController.applyCardClass(
        draftWith('766*')
            .copyWith(ocrOriginal: const OcrOriginal(cardNumber: '766*')),
        cards,
        master,
      );
      expect(d.cardNumber, '766*');
      expect(d.ocrOriginal?.cardNumber, '766*');
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

  group('자리가 서로 어긋나지 않는가', () {
    List<String?> slots(String raw) => CardDirectory.slotsOf(raw)!;

    test('둘 다 아는 자리인데 값이 다를 때만 어긋난다', () {
      expect(CardDirectory.compatible(slots('7662'), slots('7663')), isFalse);
      expect(CardDirectory.compatible(slots('7662'), slots('7662')), isTrue);
    });

    test('한쪽이 가려진 자리면 어긋났다고 말할 근거가 없다', () {
      // 양방향이다. 매입내역에는 앱이 적은 `766*` 가 섞여 있어서, 조회값이
      // 패턴일 때와 과거 행이 패턴일 때가 둘 다 생긴다.
      expect(CardDirectory.compatible(slots('766*'), slots('7662')), isTrue);
      expect(CardDirectory.compatible(slots('7662'), slots('766*')), isTrue);
      expect(CardDirectory.compatible(slots('*66*'), slots('7663')), isTrue);
    });

    test('길이가 달라도 뒤에서 맞춰 겹치는 구간만 본다', () {
      // 매입내역에는 뒤 4자리만 적힌 과거 행이 있고, 영수증은 번호를
      // 통째로 찍어준다. 뒤에서 맞추지 않으면 둘이 영원히 안 걸린다.
      expect(
        CardDirectory.compatible(slots('7662'), slots('5525-76**-****-7662')),
        isTrue,
      );
      expect(
        CardDirectory.compatible(slots('766*'), slots('5525-76**-****-7662')),
        isTrue,
      );
      // 겹치는 구간에서 어긋나면 다른 카드다.
      expect(
        CardDirectory.compatible(slots('7663'), slots('5525-76**-****-7662')),
        isFalse,
      );
      // 짧은 쪽이 모르는 앞자리는 가려진 자리와 같다 — 어긋남이 아니다.
      expect(
        CardDirectory.compatible(
          slots('9410-19**-****-7662'),
          slots('7662'),
        ),
        isTrue,
      );
    });

    test('네 자리가 아니면 비교하지 않는다', () {
      // 뒤 두 자리만 맞는 카드는 여러 장이다. 조용히 아무 카드나 걸리는
      // 것보다 false 가 낫다.
      expect(
        CardDirectory.compatible(<String?>['7', '6'], slots('7662')),
        isFalse,
      );
    });
  });

  group('매입내역으로 만든 카드 이력', () {
    test('행에서 분류코드와 카드 자리를 뽑는다', () {
      final h = CardClassHistory.fromRows(<List<Object?>>[
        past(44, '7662'),
        past('24', '3356'),
      ]);
      expect(h.rowCount, 2);
      expect(h.countsFor(CardDirectory.slotsOf('7662')!), <int, int>{44: 1});
      expect(h.countsFor(CardDirectory.slotsOf('3356')!), <int, int>{24: 1});
    });

    test('숫자가 하나도 없는 행은 버린다 — 모든 조회에 걸린다', () {
      // `****` 를 남겨두면 아무 카드로 조회해도 그 행의 분류가 끌려온다.
      final h = CardClassHistory.fromRows(<List<Object?>>[
        past(44, '****'),
        past(24, '카드없음'),
        past(3, ''),
      ]);
      expect(h.rowCount, 0);
      expect(h.countsFor(CardDirectory.slotsOf('7662')!), isEmpty);
    });

    test('분류코드가 숫자가 아니면 버린다 — 그 행으로는 분류를 못 정한다', () {
      final h = CardClassHistory.fromRows(<List<Object?>>[
        past('', '7662'),
        past('비목', '7662'),
      ]);
      expect(h.rowCount, 0);
    });

    test('컬럼이 모자란 행에서 터지지 않는다', () {
      final h = CardClassHistory.fromRows(const <List<Object?>>[
        <Object?>[44],
        <Object?>[44, '이름'],
        <Object?>[],
      ]);
      expect(h.rowCount, 0);
    });

    test('자리 호환으로 센다 — 완전일치만 보면 과거 패턴 행을 놓친다', () {
      final h = CardClassHistory.fromRows(<List<Object?>>[
        past(44, '766*'),
        past(44, '7662'),
      ]);
      // 조회값이 숫자 네 자리든 패턴이든 두 행이 다 걸린다.
      expect(h.countsFor(CardDirectory.slotsOf('7662')!), <int, int>{44: 2});
      expect(h.countsFor(CardDirectory.slotsOf('766*')!), <int, int>{44: 2});
      // 아는 자리가 어긋나면 안 걸린다.
      expect(h.countsFor(CardDirectory.slotsOf('7663')!), <int, int>{44: 1});
    });

    test('건수 많은 것부터, 같으면 코드 오름차순이다', () {
      // 문구가 호출마다 뒤바뀌면 사용자가 다른 결과로 읽는다.
      final h = CardClassHistory.fromRows(<List<Object?>>[
        past(44, '7662'),
        past(24, '7662'),
        past(24, '7662'),
        past(3, '7662'),
      ]);
      expect(h.countsFor(CardDirectory.slotsOf('7662')!).keys.toList(), <int>[
        24,
        3,
        44,
      ]);
    });

    test('뒤 4자리만 적힌 옛 행도 전체 번호 조회에 걸린다', () {
      // 카드번호 칸이 전체 번호로 바뀌기 전에 들어간 행이 시트에 그대로
      // 남아 있다. 못 걸리면 그 카드의 이력이 하루아침에 사라진다.
      final h = CardClassHistory.fromRows(<List<Object?>>[
        past(44, '7662'),
        past(44, '5525-76**-****-7662'),
      ]);
      expect(
        h.countsFor(CardDirectory.slotsOf('5525-76**-****-7662')!),
        <int, int>{44: 2},
      );
      // 앞자리가 어긋나는 행은 안 걸린다 — 전체로 보면 다른 카드다.
      expect(
        h.countsFor(CardDirectory.slotsOf('9410-19**-****-7662')!),
        <int, int>{44: 1},
        reason: '뒤 4자리만 적힌 옛 행은 앞자리를 모르므로 여전히 걸린다',
      );
    });

    test('빈 색인은 아무것도 돌려주지 않는다', () {
      expect(
        CardClassHistory.empty.countsFor(CardDirectory.slotsOf('7662')!),
        isEmpty,
      );
    });
  });

  group('카드보유내역에 없으면 매입내역을 본다', () {
    const master = {3: '법인(신용)', 24: 'CTS(체크)', 44: '글로벌팁스(카드)'};

    /// 그 카드가 **없는** 카드보유내역. 폴백이 돌아야 하는 상황이다.
    final cards = CardDirectory.fromRows(<List<Object?>>[
      row('9410-19**-****-3356', 24),
    ]);

    EntryDraft draftWith(String? number) =>
        EntryDraft(evidencePath: '/tmp/x.jpg', cardNumber: number);

    test('과거가 한 분류로 모이면 채우고 추정이라고 적는다', () {
      final history = CardClassHistory.fromRows(<List<Object?>>[
        past(44, '7662'),
        past(44, '7662'),
        past(44, '7662'),
      ]);
      final d = ReviewController.applyCardClass(
        draftWith('7662'),
        cards,
        master,
        history: history,
      );
      expect(d.classCode, 44);
      expect(d.className, '글로벌팁스(카드)');
      // 확정 매칭과 같은 모양으로 보이면 사용자가 검토 없이 지나간다.
      expect(d.classReason, contains('추정'));
      expect(d.classReason, contains('3건'));
      expect(d.cardNotice, isNull);
    });

    test('추정은 cardClass 에 넣지 않는다 — 고쳐도 경고가 붙으면 안 된다', () {
      // `cardClass` 는 "카드가 정한 사실" 칸이다. 추정에 그 경고를 붙이면
      // 맞는 선택에도 "카드가 정한 분류는 …" 이 뜬다.
      final history = CardClassHistory.fromRows(<List<Object?>>[
        past(44, '7662'),
      ]);
      final d = ReviewController.applyCardClass(
        draftWith('7662'),
        cards,
        master,
        history: history,
      );
      expect(d.cardClass, isNull);
      expect(d.copyWith(classCode: 3).classDiffersFromCard, isFalse);
    });

    test('번호를 좁혀 적지 않는다 — 실제 번호를 아는 사람이 없다', () {
      // 카드보유내역에 없는 카드라 `766*` 가 어느 번호인지 알 길이 없다.
      final history = CardClassHistory.fromRows(<List<Object?>>[
        past(44, '7662'),
      ]);
      final d = ReviewController.applyCardClass(
        draftWith('766*'),
        cards,
        master,
        history: history,
      );
      expect(d.classCode, 44);
      expect(d.cardNumber, '766*');
      expect(d.classReason, contains('766*'));
    });

    test('과거가 갈리면 자동으로 안 고르고 후보를 준다', () {
      // 추정끼리 다투는 것이라 카드가 겹쳤을 때보다 근거가 더 약하다.
      final history = CardClassHistory.fromRows(<List<Object?>>[
        past(44, '7662'),
        past(24, '7662'),
      ]);
      final d = ReviewController.applyCardClass(
        draftWith('7662'),
        cards,
        master,
        history: history,
      );
      expect(d.classCode, isNull);
      expect(d.classSuggestions.length, 2);
      expect(d.cardNotice, contains('선택해주십시오'));
      expect(d.cardNotice, contains('2건'));
    });

    test('이력에도 없으면 두 곳 다 봤다고 말한다', () {
      final history = CardClassHistory.fromRows(<List<Object?>>[
        past(44, '9999'),
      ]);
      final d = ReviewController.applyCardClass(
        draftWith('7662'),
        cards,
        master,
        history: history,
      );
      expect(d.classCode, ReviewController.defaultClassCode);
      expect(d.cardNotice, contains('찾지 못했습니다'));
      expect(d.cardNotice, contains('매입내역 과거 건에도 없습니다'));
    });

    test('이력을 못 읽었으면 봤다고 하지 않는다', () {
      // 이력을 못 읽은 것과 봤는데 없는 것은 사용자가 할 일이 다르다.
      final d = ReviewController.applyCardClass(
        draftWith('7662'),
        cards,
        master,
      );
      expect(d.cardNotice, contains('찾지 못했습니다'));
      expect(d.cardNotice, isNot(contains('매입내역')));
    });

    test('미사용 카드로 걸리면 이력을 보지 않는다', () {
      // 그쪽은 카드보유내역에 분류코드가 이미 적혀 있다. 과거 이력으로 덮으면
      // "지금 안 쓰는 카드다" 를 아무도 모르고 시트가 낡은 채로 남는다.
      final withInactive = CardDirectory.fromRows(<List<Object?>>[
        row('5525-76**-****-7662', 44, active: 'X'),
      ]);
      final history = CardClassHistory.fromRows(<List<Object?>>[
        past(24, '7662'),
      ]);
      final d = ReviewController.applyCardClass(
        draftWith('7662'),
        withInactive,
        master,
        history: history,
      );
      // 이력의 24 를 쓰지 않았다. 못 정한 셈이므로 기본값이 들어간다.
      expect(d.classCode, isNot(24));
      expect(d.classCode, ReviewController.defaultClassCode);
      expect(d.cardNotice, contains('사용하지 않는'));
    });

    test('분류명을 못 푸는 코드만 걸리면 폴백이 없던 것처럼 된다', () {
      // 이름 없이 코드만 넣으면 회계 담당자가 보는 분류명 칸이 빈다.
      final history = CardClassHistory.fromRows(<List<Object?>>[
        past(99, '7662'),
      ]);
      final d = ReviewController.applyCardClass(
        draftWith('7662'),
        cards,
        master,
        history: history,
      );
      // 이름을 못 푸는 99 는 버린다. 폴백이 없던 것과 같은 상태가 되므로
      // 기본값이 들어가고, 근거에 "추정" 이 적히지 않는다.
      expect(d.classCode, ReviewController.defaultClassCode);
      expect(d.classReason, isNot(contains('추정')));
      expect(d.cardNotice, contains('찾지 못했습니다'));
    });

    test('카드보유내역에서 찾았으면 이력을 보지 않는다', () {
      // 1차 출처가 답을 줬으면 추정이 끼어들 자리가 없다.
      final history = CardClassHistory.fromRows(<List<Object?>>[
        past(44, '3356'),
      ]);
      final d = ReviewController.applyCardClass(
        draftWith('3356'),
        cards,
        master,
        history: history,
      );
      expect(d.classCode, 24);
      // 뒤 4자리만 읽은 건이라 앞자리는 색인이 메웠다("추정").
      expect(d.classReason, '카드 9410-19**-****-3356 · CTS(체크) (3356 로 추정)');
      expect(d.cardClass?.code, 24);
    });
  });
}
