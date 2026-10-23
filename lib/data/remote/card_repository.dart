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

import 'package:bodit_app/models/class_choice.dart';
import 'package:flutter/foundation.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/googleapis_auth.dart' as gapis;

/// 카드 한 장.
@immutable
class CardInfo {
  const CardInfo({
    required this.last4,
    required this.classCode,
    required this.active,
    this.bank = '',
    this.scope = '',
    this.classNameOnSheet = '',
  });

  /// 카드번호 뒤 4자리. **앞자리는 애초에 시트에도 없다** —
  /// 카드 시트가 이미 `5531-46**-****-3927` 로 마스킹해서 들고 있다.
  final String last4;

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

/// 뒤 4자리로 카드를 찾는 색인.
///
/// 뒤 4자리는 **열쇠가 아니다.** 지금은 21장이 전부 다르지만 카드가 늘면
/// 언제든 겹칠 수 있다. 그래서 하나가 아니라 **목록**을 돌려준다 —
/// 조용히 첫 번째를 고르면 겹치는 순간부터 절반이 틀린 예산에 잡힌다.
@immutable
class CardDirectory {
  const CardDirectory(this._byLast4);

  /// 시트 행들로 색인을 만든다. **순수 함수다** — 네트워크 없이 테스트한다.
  factory CardDirectory.fromRows(List<List<Object?>> rows) {
    final out = <String, List<CardInfo>>{};
    for (final row in rows) {
      final last4 = last4Of(_cell(row, 2));
      if (last4 == null) continue;

      // 분류코드가 비었거나 숫자가 아니면 그 행은 쓸모가 없다 — 분류를 못 정한다.
      // 시트 쪽 실수이므로 조용히 건너뛰되, 그 카드는 "못 찾음" 으로 떨어진다.
      final code = int.tryParse(_cell(row, 3));
      if (code == null) continue;

      (out[last4] ??= <CardInfo>[]).add(
        CardInfo(
          last4: last4,
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

  final Map<String, List<CardInfo>> _byLast4;

  static const empty = CardDirectory(<String, List<CardInfo>>{});

  /// 그 뒤 4자리를 가진 카드 전부 — 미사용 카드까지 포함한다.
  List<CardInfo> find(String last4) =>
      _byLast4[last4.trim()] ?? const <CardInfo>[];

  /// 그중 지금 쓰는 카드만.
  List<CardInfo> findActive(String last4) =>
      find(last4).where((c) => c.active).toList();

  int get cardCount => _byLast4.values.fold(0, (a, v) => a + v.length);

  /// 마스킹된 카드번호에서 뒤 4자리를 뽑는다.
  ///
  /// 시트 표기는 `5531-46**-****-3927` 인데, 저쪽이 공백이나 구분자를 바꿔도
  /// 버티도록 **맨 뒤 연속된 숫자 4자리**만 본다. 사용자/OCR 이 `3927` 처럼
  /// 네 자리만 줘도 같은 규칙으로 걸린다.
  static String? last4Of(String raw) {
    final m = RegExp(r'(\d{4})\D*$').firstMatch(raw.trim());
    return m?.group(1);
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
