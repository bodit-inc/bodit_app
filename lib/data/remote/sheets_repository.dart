/// 매입내역 시트 읽기·쓰기.
///
/// 컬럼 계약의 단일 원천은 위키다:
///   ~/llm-wiki-template/wiki/projects/bodit-app/sheet-schema.md
///
/// **append 만 한다.** 기존 행을 고치거나 지우지 않는다(ADR Decision 2).
/// 그래서 행을 지목할 일이 없고 UUID 키 컬럼도 없다.
/// 예외는 읽기다 — 비목·분류코드 추천을 위해 과거 행을 **읽는** 것은 한다.
library;

import 'package:bodit_app/data/remote/card_repository.dart';
import 'package:bodit_app/models/category_tally.dart';
import 'package:bodit_app/models/sheet_row.dart';
import 'package:flutter/foundation.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/googleapis_auth.dart' as gapis;

/// 과거 이력에서 뽑은 **비목** 추천. 근거를 같이 들고 다닌다 —
/// 근거 없이 채워두면 사용자가 못 믿고 전부 다시 확인한다.
///
/// **분류는 여기서 제안하지 않는다.** 예전엔 `classCode`·`className` 도 같이
/// 들고 있었지만 아무도 읽지 않았다 — 어느 예산으로 집행됐는지는 긁은 카드가
/// 이미 정해놨고(`CardDirectory`), 업체 이력은 거기에 할 말이 없다.
/// 들고만 있으면 언젠가 누가 쓴다.
@immutable
class VendorSuggestion {
  const VendorSuggestion({
    required this.categoryTallies,
    required this.totalCount,
    this.recentDescriptions = const <String>[],
  }) : assert(categoryTallies.length > 0, '후보가 없으면 추천이 아니다');

  /// 이 업체를 어떤 비목으로 처리했는지, **건수 많은 것부터.**
  ///
  /// 하나로 줄여서 돌려주지 않는다. 이력이 갈린 업체가 실제로 있고(문고에서
  /// 책도 사고 간식도 산다), 그때 1등만 보여주면 사용자는 나머지가 있었다는
  /// 사실조차 모른 채 추천을 그대로 제출한다.
  final List<CategoryTally> categoryTallies;

  /// 업체명이 맞은 과거 행 수. 1등의 건수가 아니라 **전체**다 —
  /// "7건 중 4건" 의 7.
  final int totalCount;

  /// 이 업체로 과거에 쓴 **내역** 들. 최근 것부터, 중복 제거.
  ///
  /// **자동으로 채우지 않는다.** 비목과 성격이 다르다 —
  /// 비목은 업체가 정해지면 거의 안 바뀌지만("영풍문고 = 도서인쇄비"),
  /// 내역은 건마다 달라진다("8월 도서" → "9월 도서").
  /// 지난 값을 자동으로 넣으면 **9월에 8월 도서가 조용히 들어간다.**
  /// 그래서 후보로만 보여주고 고르는 건 사용자가 한다.
  final List<String> recentDescriptions;

  /// 화면에 채워 넣을 비목. 가장 많이 쓴 것.
  String get expenseCategory => categoryTallies.first.category;

  /// 그 비목으로 처리한 건수. [totalCount] 와 같으면 이력이 갈리지 않았다는 뜻이다.
  int get matchCount => categoryTallies.first.count;

  /// 추천의 근거 문구. **"모두" 를 함부로 쓰지 않는다.**
  ///
  /// 예전에는 이력이 갈려도 "N건 모두" 로 적었다. 도서인쇄비 4건 + 복리후생비
  /// 3건인 업체에 "지난 4건 모두 도서인쇄비였습니다" 가 떴다 — 7건 중 4건인데
  /// 전부라고 말하고, 나머지 3건은 화면에서 사라졌다. 확인이 **가장 필요한
  /// 건**에 가장 확신 있는 문구가 나간 셈이다.
  ///
  /// **마침표로 끝낸다.** 분류 근거(`classReason`)는 "카드 3927 · 법인(신용)"
  /// 처럼 라벨이라 마침표가 없지만, 이쪽은 완결된 문장이다.
  String get reason => categoryTallies.length == 1
      ? '$totalCount건 모두 $expenseCategory였습니다.'
      : '$totalCount건 중 $matchCount건이 $expenseCategory였습니다.';

  /// 시트 행들로 추천을 만든다. **순수 함수다** — 네트워크 없이 테스트한다.
  ///
  /// 행 모양은 [SheetsRepository.suggestForVendor] 가 읽는 범위와 같다:
  /// `E 비목 · F 내역 · G 업체명 · H 분류코드 · I 분류명`.
  /// 비목이 비었거나 분류코드가 숫자가 아닌 행은 **아직 완성되지 않은 행**이라
  /// 세지 않는다 — 그런 행을 근거로 추천하면 사용자가 못 믿는다.
  static VendorSuggestion? fromRows(
    List<List<Object?>> rows, {
    required String vendor,
  }) {
    final needle = _normalize(vendor);
    if (needle.isEmpty) return null;

    // 비목별 건수. **조합(비목+분류코드)이 아니라 비목으로 센다** —
    // 조합으로 세면 같은 비목이 분류코드 둘로 쪼개져서, 합이 더 많은 비목이
    // 1등을 놓친다(도서인쇄비 3+2건 vs 복리후생비 4건 → 4건짜리가 1등).
    // 분류는 어차피 카드가 정하므로 여기서 쪼갤 이유가 없다.
    final counts = <String, int>{};
    // 내역은 세지 않고 **등장 순서**대로 모은다 — 시트가 append-only 라
    // 뒤에 있는 게 최근이다. LinkedHashMap 의 삽입 순서로 중복을 지운다.
    final descriptions = <String, void>{};
    var total = 0;

    for (final row in rows) {
      if (row.length < 5) continue;
      if (_normalize('${row[2]}') != needle) continue;

      final category = '${row[0]}'.trim();
      if (category.isEmpty || int.tryParse('${row[3]}'.trim()) == null) {
        continue;
      }

      total++;
      counts[category] = (counts[category] ?? 0) + 1;

      final desc = '${row[1]}'.trim();
      if (desc.isNotEmpty) {
        // 다시 넣어 최신 등장 위치로 끌어올린다.
        descriptions.remove(desc);
        descriptions[desc] = null;
      }
    }

    if (counts.isEmpty) return null;

    // 건수 많은 것부터. **같으면 시트에 먼저 나온 쪽이 먼저다** —
    // `List.sort` 는 안정 정렬이 아니라서 동률을 그냥 두면 같은 시트를
    // 조회할 때마다 칩 순서가 바뀔 수 있다.
    final seen = counts.keys.toList();
    final tallies =
        counts.entries
            .map((e) => CategoryTally(category: e.key, count: e.value))
            .toList()
          ..sort((a, b) {
            final byCount = b.count.compareTo(a.count);
            if (byCount != 0) return byCount;
            return seen.indexOf(a.category).compareTo(seen.indexOf(b.category));
          });

    return VendorSuggestion(
      categoryTallies: tallies,
      totalCount: total,
      // 최근 것부터 최대 6개. 더 보여주면 고르는 게 일이 된다.
      recentDescriptions: descriptions.keys.toList().reversed.take(6).toList(),
    );
  }

  /// 업체명 비교용 정규화. 공백·괄호 표기 차이로 못 찾는 걸 막는다.
  static String _normalize(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
}

/// 매입내역 한 행에서 뽑은 것 — 카드번호 자리들과 그때 쓴 분류코드.
@immutable
class _CardClassRow {
  const _CardClassRow(this.slots, this.code);

  final List<String?> slots;
  final int code;
}

/// 매입내역 과거 행으로 만든 **카드 → 분류** 색인.
///
/// 분류의 1차 출처는 카드보유내역이다(`CardDirectory`). 이건 **그 시트에 그
/// 카드가 아직 없을 때의 두 번째 근거**다 — 운영팀이 카드를 늦게 적는 일이
/// 있고, 그 사이에 올라온 영수증은 분류를 통째로 못 정한다. 그런데 같은 카드로
/// 전에 제출한 건이 있으면 **어느 분류였는지는 매입내역에 이미 적혀 있다.**
///
/// 업체 이력 추천(`suggestForVendor`)과는 다르다. 그쪽은 "같은 업체면 같은
/// 비목" 이라는 경향이고, 이쪽은 **같은 카드**다 — 분류를 정하는 것은 어차피
/// 카드이므로 근거의 종류가 같고, 다만 출처가 마스터가 아니라 과거 기록이다.
/// 그래서 결과는 **추정**으로 표시한다(`applyCardClass`).
///
/// 매입내역에는 **뒤 4자리밖에 없다.** 그래서 앞자리로 좁히는 일은 여기서도
/// 못 한다. 대신 자리 호환 매칭으로 가려진 자리를 넘어간다 — 그 칸에는 앱이
/// 적은 `766*` 같은 패턴이 섞여 있다.
@immutable
class CardClassHistory {
  const CardClassHistory(this._rows);

  /// 시트 행들로 색인을 만든다. **순수 함수다** — 네트워크 없이 테스트한다.
  ///
  /// 행 모양은 `cardClassHistory` 가 읽는 범위와 같다: `H 분류코드 · I 분류명
  /// · J 카드번호`. **I열은 쓰지 않는다** — 분류명의 출처는 `_분류마스터`
  /// 하나다(두 시트가 어긋난 적이 있다. `card_repository.dart` 주석 참조).
  factory CardClassHistory.fromRows(List<List<Object?>> rows) {
    final out = <_CardClassRow>[];
    for (final row in rows) {
      if (row.length < 3) continue;
      final code = int.tryParse('${row[0] ?? ''}'.trim());
      if (code == null) continue;

      final slots = CardDirectory.slotsOf('${row[2] ?? ''}');
      // 숫자가 하나도 없는 행(`****`·`카드없음`·빈칸)은 버린다 —
      // 호환 매칭에서 **모든 조회에 걸려서** 아무 분류나 끌어온다.
      if (slots == null || !CardDirectory.hasAnyDigit(slots)) continue;

      out.add(_CardClassRow(slots, code));
    }
    return CardClassHistory(out);
  }

  final List<_CardClassRow> _rows;

  static const empty = CardClassHistory(<_CardClassRow>[]);

  /// 그 자리들과 어긋나지 않는 과거 행을 세어 **분류코드 → 건수**로 돌려준다.
  ///
  /// 건수가 많은 것부터, 같으면 코드 오름차순이다 — 화면 문구가 호출마다
  /// 뒤바뀌면 사용자가 다른 결과로 읽는다.
  Map<int, int> countsFor(List<String?> slots) {
    final counts = <int, int>{};
    for (final r in _rows) {
      if (!CardDirectory.compatible(r.slots, slots)) continue;
      counts[r.code] = (counts[r.code] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()
      ..sort(
        (a, b) => a.value != b.value
            ? b.value.compareTo(a.value)
            : a.key.compareTo(b.key),
      );
    return Map<int, int>.fromEntries(sorted);
  }

  /// 색인에 들어온 과거 행 수. 진단용이다.
  int get rowCount => _rows.length;
}

class SheetsRepository {
  const SheetsRepository({
    required this.spreadsheetId,
    this.dataSheetName = '매입내역',
  });

  final String spreadsheetId;

  /// 매입내역 탭. 추천 조회에만 쓴다 — append 는 `SheetRow.sheetName` 이 정한다.
  final String dataSheetName;

  /// 한 행을 그 항목이 속한 탭 맨 아래에 붙인다.
  ///
  /// `SheetRow` 를 받으므로 2차 사업비·3차 월결산이 와도 이 함수 하나면 된다.
  ///
  /// `values.append` 는 서버가 마지막 행을 찾아 붙이므로,
  /// 읽고→계산하고→쓰는 방식과 달리 동시 제출에서 서로 덮어쓰지 않는다.
  Future<void> appendRow({
    required gapis.AuthClient client,
    required SheetRow row,
  }) async {
    final api = sheets.SheetsApi(client);
    await api.spreadsheets.values.append(
      sheets.ValueRange(values: <List<Object>>[row.toSheetRow()]),
      spreadsheetId,
      row.sheetName,
      // USER_ENTERED = 시트가 날짜·숫자로 해석하게 둔다.
      // RAW 로 하면 전부 문자열이 돼서 회계 담당자의 수식·필터가 깨진다.
      valueInputOption: 'USER_ENTERED',
      insertDataOption: 'INSERT_ROWS',
    );
  }

  /// 매입내역 과거 행에서 **카드 → 분류** 색인을 만든다.
  ///
  /// 카드보유내역에 없는 카드의 분류를 추정하는 데 쓴다([CardClassHistory]).
  /// 업체 이력과 **같은 구간**(최근 [maxRows] 행)을 본다 — 시트 전체를 매번
  /// 읽을 이유가 없고, 카드가 바뀌면 최근 행이 먼저 말해준다.
  Future<CardClassHistory> cardClassHistory({
    required gapis.AuthClient client,
    int maxRows = 2000,
  }) async {
    final api = sheets.SheetsApi(client);
    // H:J = 분류코드 · 분류명 · 카드번호. 가운데 I열은 **읽고도 버린다** —
    // 가운데를 건너뛰는 범위 표기가 없어서 같이 들어올 뿐이다.
    final res = await api.spreadsheets.values.get(
      spreadsheetId,
      "'$dataSheetName'!H2:J${maxRows + 1}",
    );
    return CardClassHistory.fromRows(res.values ?? <List<Object?>>[]);
  }

  /// 업체명으로 과거 처리를 찾아 **비목**을 제안한다.
  ///
  /// **자동완성의 실제 승부처가 여기다.** OCR 은 비목을 못 뽑는다 —
  /// 영수증에 안 적혀 있다. 이 조회가 잘 되면 사용자가 34개 중에서 고를 일이 없다.
  ///
  /// 분류는 제안하지 않는다 — 카드가 정한다([VendorSuggestion] 주석 참조).
  ///
  /// 시트 전체를 매번 읽지 않도록 [maxRows] 로 최근 구간만 본다.
  Future<VendorSuggestion?> suggestForVendor({
    required gapis.AuthClient client,
    required String vendor,
    int maxRows = 2000,
  }) async {
    final api = sheets.SheetsApi(client);
    // E:I = 비목 · 내역 · 업체명 · 분류코드 · 분류명
    final res = await api.spreadsheets.values.get(
      spreadsheetId,
      "'$dataSheetName'!E2:I${maxRows + 1}",
    );
    // 세는 일은 `VendorSuggestion.fromRows` 가 한다 — 여기 두면 네트워크
    // 없이는 못 돌려서, 1등을 고르는 규칙을 테스트로 고정할 수 없다.
    return VendorSuggestion.fromRows(
      res.values ?? <List<Object?>>[],
      vendor: vendor,
    );
  }
}

/// 비목·분류 마스터. **하드코딩하지 않는다** — 사업이 하나 생길 때마다
/// 앱을 재배포하게 된다. 시트의 별도 탭에서 읽어 캐시한다.
/// Sheets API 의 400 은 원인이 여럿인데 메시지가 불친절하다.
/// 가장 흔한 두 가지를 짚어준다.
Never _explainSheetsError(Object e, String spreadsheetId, String range) {
  if (e is sheets.DetailedApiRequestError && e.status == 400) {
    // 스프레드시트 ID 는 보통 44자다. 그보다 짧으면 **변환되지 않은 업로드 파일**일
    // 가능성이 크다 — Drive 는 이제 xlsx 를 자동 변환하지 않는다.
    // 그런 파일은 Sheets 에서 열려서 겉보기엔 멀쩡한데 Sheets API 는 못 읽는다.
    if (spreadsheetId.length < 40) {
      throw StateError(
        '시트를 읽지 못했습니다 (400).\n\n'
        'SPREADSHEET_ID 가 ${spreadsheetId.length}자입니다. '
        'Google 스프레드시트 ID 는 보통 44자입니다.\n'
        '엑셀 파일은 Drive 에 올려도 자동 변환되지 않습니다 — '
        '겉보기엔 열리지만 Sheets API 는 읽지 못합니다.\n\n'
        '그 파일을 열고 [파일] → [Google Sheets로 저장] 을 누른 뒤, '
        '새로 생긴 파일의 ID 를 .env 에 넣어주세요.\n\n'
        '원문: ${e.message}',
      );
    }
    throw StateError(
      '시트를 읽지 못했습니다 (400).\n'
      '범위: $range\n'
      '탭 이름이 정확한지 확인해 주세요.\n\n'
      '원문: ${e.message}',
    );
  }
  // 400 이 아니면 원래 예외를 그대로 올린다 — 여기서 감싸면 원인이 가려진다.
  // ignore: only_throw_errors — 받은 예외를 그대로 다시 던지는 것이라 안전하다.
  throw e;
}

class MasterDataRepository {
  const MasterDataRepository({
    required this.spreadsheetId,
    this.categorySheet = '_비목마스터',
    this.classSheet = '_분류마스터',
  });

  final String spreadsheetId;
  final String categorySheet;
  final String classSheet;

  /// 비목 34개(늘어날 수 있다).
  Future<List<String>> categories(gapis.AuthClient client) async {
    final api = sheets.SheetsApi(client);
    // 시트 이름은 작은따옴표로 감싼다. 밑줄로 시작하거나 한글·공백이 섞이면
    // 따옴표 없이는 A1 표기가 깨진다.
    final range = "'$categorySheet'!A2:A";
    final sheets.ValueRange res;
    try {
      res = await api.spreadsheets.values.get(spreadsheetId, range);
    } on Object catch (e) {
      _explainSheetsError(e, spreadsheetId, range);
    }
    return (res.values ?? <List<Object?>>[])
        .where((r) => r.isNotEmpty)
        .map((r) => '${r[0]}'.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// 분류코드 → 분류명.
  ///
  /// 시트에 수식을 두지 않으므로(위키 참조) **앱이 이걸로 분류명을 채운다.**
  Future<Map<int, String>> classNames(gapis.AuthClient client) async {
    final api = sheets.SheetsApi(client);
    final res = await api.spreadsheets.values.get(
      spreadsheetId,
      "'$classSheet'!A2:B",
    );
    final out = <int, String>{};
    for (final r in res.values ?? <List<Object?>>[]) {
      if (r.length < 2) continue;
      final code = int.tryParse('${r[0]}'.trim());
      if (code != null) out[code] = '${r[1]}'.trim();
    }
    return out;
  }
}
