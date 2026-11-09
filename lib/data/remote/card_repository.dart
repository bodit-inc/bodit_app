/// 카드보유내역 시트 읽기. **분류를 정하는 건 여기다.**
///
/// ## 왜 과거 이력이 아니라 카드가 분류를 정하는가
///
/// 업체 이력 추천(`SheetsRepository.suggestForVendor`)은 추측이다 —
/// "영풍문고는 지난 6건 모두 도서인쇄비였다" 는 과거의 경향일 뿐이다.
/// 그런데 **분류는 추측할 대상이 아니다.** 어느 예산으로 집행됐는지는
/// 긁은 카드가 이미 정해놨다. 같은 업체에서 같은 걸 사도 법인카드로 긁으면
/// `법인(신용)`, 사업비 카드로 긁으면 그 사업의 분류다.
///
/// 그래서 **비목은 업체 이력, 분류는 카드**가 담당한다.
///
/// ## 카드번호는 **전체**로 대조한다
///
/// 예전에는 뒤 4자리만 들고 조회했다. 뒤 4자리는 열쇠가 아니라서 겹치면
/// 사용자에게 물어야 했는데, 영수증에는 앞자리도 **인쇄돼 있었다** —
/// `5531-46**-****-3927` 의 `5531-46` 을 버리고 `3927` 만 보고 있었던 셈이다.
/// 앞 6자리(BIN)는 카드사·상품이 갈리는 자리라, 같이 보면 뒤 4자리가 겹치는
/// 두 장도 저절로 갈린다.
///
/// 그래서 색인의 단위가 **번호 전체**다. 다만 양쪽 다 가려진 자리가 섞여
/// 있으므로(카드 시트도 `5531-46**-****-3927` 로 마스킹해서 들고 있다)
/// 비교는 자리 단위 호환 판정이다(`CardDirectory.compatible`) — 둘 다 아는
/// 자리인데 값이 다를 때만 "다른 카드" 다.
///
/// **길이가 달라도 뒤에서 맞춰 비교한다.** 영수증이 뒤 4자리만 찍어주는
/// 경우(`3927`)가 남아 있고, 매입내역 과거 행에는 뒤 4자리만 적힌 행이
/// 그대로 있다. 뒤에서 맞추는 쪽이 둘을 같이 받는다.
///
/// ## 이 시트는 우리 것이 아니다
///
/// 매입내역과 **다른 스프레드시트**고, 운영팀이 관리한다. 우리 계정으로는
/// 보기 전용이다. 그래서 두 가지를 조심한다:
///
///   - 탭 이름을 믿지 않는다. 범위를 탭 이름 없이 주면 Sheets API 가
///     **첫 번째 시트**를 쓴다 — 저쪽이 탭 이름을 바꿔도 안 깨진다
///   - **카드 시트의 분류명(E열)을 쓰지 않는다.** 분류명은 `_분류마스터`에서
///     푼다. 실제로 두 시트가 어긋난 적이 있다(카드 시트 44 = 글로벌팁스(카드),
///     마스터 44 = 딥테크(카드)). 어느 쪽을 읽었느냐에 따라 시트에 들어가는
///     값이 달라지면 안 되므로 **분류명의 출처는 마스터 하나**로 고정한다.
///     E열은 진단용으로만 들고 있는다
///
/// 컬럼 계약: `A no. · B 은행 · C 카드번호 · D 분류코드 · E 분류명 · F 구분 · G 현재사용여부`
library;

import 'dart:math' as math;

import 'package:bodit_app/models/class_choice.dart';
import 'package:flutter/foundation.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/googleapis_auth.dart' as gapis;

/// 카드 한 장.
@immutable
class CardInfo {
  const CardInfo({
    required this.number,
    required this.slots,
    required this.classCode,
    required this.active,
    this.bank = '',
    this.scope = '',
    this.classNameOnSheet = '',
  });

  /// 카드번호 **전체**, 정규화된 표기(`5531-46**-****-3927`).
  ///
  /// 가려진 자리가 섞여 있다 — 카드 시트가 애초에 마스킹해서 들고 있고,
  /// 우리가 풀 방법은 없다. 그 표기를 그대로 쓰는 것이 아니라
  /// [CardDirectory.patternOf] 로 한 번 모은 값이다(구분자는 `-`,
  /// 가려진 자리는 `*`). 같은 카드가 시트 표기 차이로 두 가지로 보이면
  /// 안 된다.
  final String number;

  /// [number] 를 자리 단위로 쪼갠 것. 숫자면 그 숫자, 가려진 자리는 null.
  /// 조회가 이걸 대조한다 — 문자열끼리 비교하면 마스크가 걸린다.
  final List<String?> slots;

  /// `_분류마스터` 의 분류코드. 이름은 여기서 풀지 않는다(위 주석).
  final int classCode;

  /// `현재사용여부` 가 `O` 인가.
  ///
  /// **false 인 카드도 버리지 않고 들고 있는다.** 버리면 "못 찾았다" 와
  /// "지금은 안 쓰는 카드다" 를 구분해줄 수 없다 — 몇 달 지난 영수증을
  /// 뒤늦게 올리는 일은 흔하고, 그때 사용자에게 할 말이 달라야 한다.
  final bool active;

  final String bank;

  /// `법인` / `사업비`. 분류코드보다 거칠어서 판단에는 안 쓰고, 화면 문구에만 쓴다.
  final String scope;

  /// 카드 시트 E열에 적힌 이름. **판단에 쓰지 않는다**(위 주석 참조).
  final String classNameOnSheet;
}

/// 카드번호로 카드를 찾는 색인.
///
/// 번호 전체를 보더라도 **열쇠는 아니다.** 양쪽 다 가려진 자리가 있어서
/// 아는 자리만 맞는 카드가 둘일 수 있다. 그래서 하나가 아니라 **목록**을
/// 돌려준다 — 조용히 첫 번째를 고르면 겹치는 순간부터 절반이 틀린 예산에
/// 잡힌다.
@immutable
class CardDirectory {
  const CardDirectory(this._cards);

  /// 시트 행들로 색인을 만든다. **순수 함수다** — 네트워크 없이 테스트한다.
  factory CardDirectory.fromRows(List<List<Object?>> rows) {
    final out = <CardInfo>[];
    for (final row in rows) {
      final slots = slotsOf(_cell(row, 2));
      // 카드번호가 없거나(빈칸) 아는 자리가 하나도 없는 행은 쓸모가 없다 —
      // 전부 가려진 번호는 **모든 조회에 걸려서** 아무 분류나 끌어온다.
      if (slots == null || !hasAnyDigit(slots)) continue;

      // 분류코드가 비었거나 숫자가 아니면 그 행은 쓸모가 없다 — 분류를 못 정한다.
      // 시트 쪽 실수이므로 조용히 건너뛰되, 그 카드는 "못 찾음" 으로 떨어진다.
      final code = int.tryParse(_cell(row, 3));
      if (code == null) continue;

      out.add(
        CardInfo(
          number: patternOf(slots),
          slots: slots,
          classCode: code,
          active: _isActive(_cell(row, 6)),
          bank: _cell(row, 1),
          classNameOnSheet: _cell(row, 4),
          scope: _cell(row, 5),
        ),
      );
    }
    return CardDirectory(out);
  }

  final List<CardInfo> _cards;

  static const empty = CardDirectory(<CardInfo>[]);

  /// 그 번호와 어긋나지 않는 카드 전부 — 미사용 카드까지 포함한다.
  ///
  /// 들어온 표기는 무엇이든 받는다(전체 번호·뒤 4자리·마스크 섞인 것).
  /// 자리를 못 뽑으면 빈 목록이다 — 억지로 맞추면 틀린 카드를 고른다.
  List<CardInfo> find(String raw) {
    final slots = slotsOf(raw);
    if (slots == null || !hasAnyDigit(slots)) return const <CardInfo>[];
    return findByPattern(slots);
  }

  /// 그중 지금 쓰는 카드만.
  List<CardInfo> findActive(String raw) =>
      find(raw).where((c) => c.active).toList();

  /// 자리별로 대조해 후보를 돌려준다. **미사용 카드도 포함한다** —
  /// 버리면 "못 찾았다" 와 "지금 안 쓰는 카드다" 를 구분해줄 수 없다.
  ///
  /// 순서는 활성 먼저, 그다음 번호 오름차순이다. 화면에 "카드 A, 카드 B"
  /// 로 나열하는 문구가 호출마다 뒤바뀌면 사용자가 다른 결과로 읽는다.
  List<CardInfo> findByPattern(List<String?> slots) {
    final out = _cards.where((c) => compatible(c.slots, slots)).toList()
      ..sort((a, b) {
        if (a.active != b.active) return a.active ? -1 : 1;
        return a.number.compareTo(b.number);
      });
    return out;
  }

  /// 두 자리 묶음이 **서로 어긋나지 않는가.** 둘 다 아는 자리인데 값이 다를
  /// 때만 false 다 — 한쪽이 가려진 자리면 어긋났다고 말할 근거가 없다.
  ///
  /// **뒤에서 맞춰 비교한다.** 길이가 다른 경우가 셋이나 있다:
  ///
  ///   - 영수증이 뒤 4자리만 찍어준 경우(`3927`) vs 시트의 전체 번호
  ///   - 매입내역 과거 행 — 전체 번호를 쓰기 전에 적힌 행은 뒤 4자리뿐이다
  ///   - 카드사마다 자리 수가 다르다(15·16자리)
  ///
  /// 겹치는 구간만 본다. 짧은 쪽이 모르는 앞자리는 **어긋났다고 말할 근거가
  /// 없는 자리**라서, 가려진 자리와 똑같이 다룬다.
  ///
  /// 4자리 미만끼리는 비교하지 않는다 — [slotsOf] 가 애초에 그런 값을
  /// 돌려주지 않지만, 호출부가 직접 만든 자리 묶음을 넘겼을 때 조용히
  /// 아무 카드나 걸리는 것보다 false 가 낫다.
  static bool compatible(List<String?> a, List<String?> b) {
    if (a.length < 4 || b.length < 4) return false;
    final n = math.min(a.length, b.length);
    for (var i = 0; i < n; i++) {
      final x = _fromEnd(a, i);
      final y = _fromEnd(b, i);
      if (x != null && y != null && x != y) return false;
    }
    return true;
  }

  /// 두 자리 묶음을 **겹쳐서** 아는 자리를 모은다. 뒤에서 맞춘다.
  ///
  /// 영수증과 카드 시트는 **서로 다른 자리를 가린다.** 영수증이 `766*` 만
  /// 찍어줬어도 시트가 `5525-76**-****-7662` 를 들고 있으면, 둘을 겹친
  /// `5525-76**-****-7662` 가 우리가 아는 전부다. 한쪽만 적으면 아는 것을
  /// 버리는 셈이다.
  ///
  /// **어긋나지 않는 두 묶음에만 쓴다**([compatible] 로 먼저 확인한다).
  /// 어긋난 자리가 있으면 먼저 온 쪽이 이기는데, 그건 틀린 번호를 만든다.
  static List<String?> merge(List<String?> a, List<String?> b) {
    final n = math.max(a.length, b.length);
    final out = List<String?>.filled(n, null);
    for (var i = 0; i < n; i++) {
      out[n - 1 - i] = _fromEnd(a, i) ?? _fromEnd(b, i);
    }
    return out;
  }

  /// 뒤에서 [i] 번째 자리. 범위를 넘으면 null — **모르는 자리**다.
  static String? _fromEnd(List<String?> slots, int i) =>
      i < slots.length ? slots[slots.length - 1 - i] : null;

  int get cardCount => _cards.length;

  /// 구분자. 자리를 맞추려면 **먼저 지워야 한다** — `5531-46**-****-766*` 의
  /// `-` 와 `*` 는 둘 다 숫자가 아니지만 하나는 구분자고 하나는 가려진 자리다.
  /// 구분자만 지우고 남은 비숫자를 마스크로 본다.
  static final _separator = RegExp(r'[-\s·./_]');

  /// 카드번호를 **자리 단위**로 뽑는다. 숫자면 그 숫자, 가려진 자리는 `null`.
  ///
  /// 길이를 자르지 않는다 — 들어온 자리 수가 그대로 나온다. 영수증이 전체
  /// 번호를 찍어줬으면 16자리, 뒤 4자리만 찍어줬으면 4자리다. 대조는
  /// [compatible] 이 뒤에서 맞춰서 한다.
  ///
  /// 마스크 문자 종류를 열거하지 않는다 — `*`·`x`·`#`·`●` 중 무엇이 올지
  /// 모르고, 목록에서 빠진 문자가 하나라도 있으면 그 영수증은 또 조회가 안 된다.
  /// 구분자를 지운 뒤 **숫자가 아닌 것은 전부 가려진 자리**로 본다.
  ///
  /// 4칸을 못 채우면 `null` 이다. `66*` 가 `?66*` 인지 `66*?` 인지 알 수 없고,
  /// 한쪽으로 가정하면 **틀린 카드를 고른다** — 분류가 통째로 틀리고 시트는
  /// append-only 라 되돌릴 수 없다.
  ///
  /// **뒤에서 맞춰 비교하므로 짧은 입력은 "뒤 N자리" 로 읽힌다.** 앞자리만
  /// 네 자리 치면(`5531`) 그 카드가 안 걸린다 — 영수증·OCR 은 번호를 통째로
  /// 주고, 사람이 손으로 칠 때도 보이는 것은 뒤쪽이라 이 가정이 맞다.
  ///
  /// 그래서 **뒤쪽의 비숫자를 떨어내지 않는다.** 카드번호 칸에 메모가 붙어
  /// 있으면(`5531-46**-****-3927 (법인)`) 자리가 밀려 그 카드를 못 찾는다 —
  /// 예전처럼 "맨 뒤 숫자 4자리" 만 봤다면 넘어갔을 경우다. 그렇다고 떨어내면
  /// 영수증에 실제로 찍히는 `766*` 의 마지막 자리가 사라져서 **자리 수가
  /// 어긋나고, 그쪽은 틀린 카드를 고르게 된다.** 둘 중에는 못 찾는 쪽이 낫다 —
  /// 못 찾으면 화면이 "번호가 맞는지 확인해주세요" 라고 말하고 분류는
  /// 기본값으로 남지만, 틀린 카드를 고르면 **틀린 예산**이 append-only
  /// 시트에 들어간다.
  static List<String?>? slotsOf(String raw) {
    final s = raw.trim().replaceAll(_separator, '');
    if (s.length < 4) return null;
    final out = <String?>[];
    for (final ch in s.split('')) {
      out.add(_isDigit(ch) ? ch : null);
    }
    return out;
  }

  /// 자리들을 표기로 되돌린다 — 가려진 자리는 `*`, **4자리마다 `-`**.
  /// 저장·문구에 이 형태를 쓴다(`5531-46**-****-3927`).
  ///
  /// 원문이 `5531 46xx xxxx 766x` 든 `5531.46##.####.766#` 든 하나로 모은다.
  /// 같은 카드가 영수증마다 다른 모양으로 시트에 들어가면 나중에 사람이
  /// 훑을 때 다른 카드로 보인다.
  ///
  /// 4로 안 나눠지는 길이(15자리 Amex 등)는 **앞에서부터** 넷씩 묶고 남는
  /// 것을 끝에 붙인다. 카드사가 인쇄하는 모양(4-6-5)과는 다르지만, 자리 수가
  /// 몇이든 같은 규칙이라 같은 카드가 두 가지로 보이지 않는다.
  static String patternOf(List<String?> slots) {
    final out = StringBuffer();
    for (var i = 0; i < slots.length; i++) {
      if (i > 0 && i % 4 == 0) out.write('-');
      out.write(slots[i] ?? '*');
    }
    return out.toString();
  }

  /// 표기를 정규화한다 — [slotsOf] 로 자리를 뽑아 [patternOf] 로 되돌린다.
  ///
  /// 자리를 못 뽑거나(`392`) 아는 자리가 하나도 없으면(`****`·`카드없음`)
  /// null 이다. **그때 원본을 버릴지는 호출부가 정한다** — OCR 이 `****` 를
  /// 읽어온 것은 "카드 결제인데 번호가 전부 가려졌다" 는 뜻이라, 빈 칸으로
  /// 만들면 "카드 결제가 아니다" 와 구분되지 않는다.
  ///
  /// OCR 결과와 사용자 입력을 **들어오는 자리에서** 한 번 모아둔다.
  /// 나중에 모으면 `5531 46xx xxxx 3927` 로 읽은 값과 정규화한 값이 달라서,
  /// 사용자가 아무것도 안 고쳤는데 "…로 인식했습니다" 가 뜬다.
  static String? normalized(String? raw) {
    if (raw == null) return null;
    final slots = slotsOf(raw);
    if (slots == null || !hasAnyDigit(slots)) return null;
    return patternOf(slots);
  }

  /// 자리가 전부 숫자인가. 참이면 가려진 자리가 없다는 뜻이다 —
  /// 카드 영수증은 대개 가려서 인쇄하므로 흔한 경우는 아니다.
  static bool isExact(List<String?> slots) => slots.every((e) => e != null);

  /// 아는 자리가 하나라도 있는가. 전부 가려졌으면(`****`·`카드없음`)
  /// 모든 카드가 걸리므로 조회하지 않는다.
  static bool hasAnyDigit(List<String?> slots) => slots.any((e) => e != null);

  static bool _isDigit(String ch) {
    final c = ch.codeUnitAt(0);
    return c >= 0x30 && c <= 0x39;
  }

  /// `현재사용여부`. 시트는 지금 `O` 만 쓰지만, 사람이 손으로 적는 칸이라
  /// 소문자·공백은 들어온다고 보고 받아준다. 그 외(`X`·빈칸)는 전부 미사용이다.
  static bool _isActive(String raw) => raw.trim().toUpperCase() == 'O';

  static String _cell(List<Object?> row, int i) =>
      i < row.length ? '${row[i] ?? ''}'.trim() : '';
}

class CardRepository {
  const CardRepository({required this.spreadsheetId, this.sheetName});

  final String spreadsheetId;

  /// 탭 이름. **보통 null 로 둔다** — 그러면 Sheets API 가 첫 번째 시트를 쓴다.
  /// 우리가 관리하지 않는 시트라 탭 이름이 바뀌어도 안 깨지는 쪽이 낫다.
  final String? sheetName;

  String get _range {
    const cells = 'A2:G';
    final name = sheetName;
    return name == null ? cells : "'$name'!$cells";
  }

  Future<CardDirectory> load(gapis.AuthClient client) async {
    final api = sheets.SheetsApi(client);
    final res = await api.spreadsheets.values.get(spreadsheetId, _range);
    return CardDirectory.fromRows(res.values ?? <List<Object?>>[]);
  }
}

/// 카드 한 장을 분류로 바꾼다. 이름은 **마스터에서** 푼다.
///
/// 마스터에 없는 코드면 null 이다 — 이름 없이 코드만 시트에 넣으면
/// 회계 담당자가 보는 분류명 칸이 빈다. 그럴 바엔 비워두고 물어보는 게 낫다.
ClassChoice? resolveClass(CardInfo card, Map<int, String> classNames) {
  final name = classNames[card.classCode];
  if (name == null || name.isEmpty) return null;
  return ClassChoice(code: card.classCode, name: name);
}
