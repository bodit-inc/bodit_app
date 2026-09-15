/// 매입내역 시트 읽기·쓰기.
///
/// 컬럼 계약의 단일 원천은 위키다:
///   ~/llm-wiki-template/wiki/projects/bodit-app/sheet-schema.md
///
/// **append 만 한다.** 기존 행을 고치거나 지우지 않는다(ADR Decision 2).
/// 그래서 행을 지목할 일이 없고 UUID 키 컬럼도 없다.
/// 예외는 읽기다 — 비목·분류코드 추천을 위해 과거 행을 **읽는** 것은 한다.
library;

import 'package:bodit_app/models/sheet_row.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/googleapis_auth.dart' as gapis;

/// 과거 이력에서 뽑은 추천. 근거를 같이 들고 다닌다 —
/// 근거 없이 채워두면 사용자가 못 믿고 전부 다시 확인한다.
class VendorSuggestion {
  const VendorSuggestion({
    required this.expenseCategory,
    required this.classCode,
    required this.className,
    required this.matchCount,
  });

  final String expenseCategory;
  final int classCode;
  final String className;

  /// 같은 업체를 이렇게 처리한 과거 건수. 화면에 "지난 N건" 으로 보여준다.
  final int matchCount;

  String get reason => '$matchCount건 모두 $expenseCategory였습니다';
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

  /// 업체명으로 과거 처리를 찾아 비목·분류코드를 제안한다.
  ///
  /// **자동완성의 실제 승부처가 여기다.** OCR 은 비목을 못 뽑는다 —
  /// 영수증에 안 적혀 있다. 이 조회가 잘 되면 사용자가 34개 중에서 고를 일이 없다.
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

    final rows = res.values;
    if (rows == null || rows.isEmpty) return null;

    final needle = _normalize(vendor);
    if (needle.isEmpty) return null;

    // (비목, 분류코드, 분류명) 조합별 등장 횟수를 센다.
    final counts = <String, int>{};
    final samples = <String, (String, int, String)>{};

    for (final row in rows) {
      if (row.length < 5) continue;
      if (_normalize('${row[2]}') != needle) continue;

      final category = '${row[0]}'.trim();
      final code = int.tryParse('${row[3]}'.trim());
      final className = '${row[4]}'.trim();
      if (category.isEmpty || code == null) continue;

      final key = '$category|$code|$className';
      counts[key] = (counts[key] ?? 0) + 1;
      samples[key] = (category, code, className);
    }

    if (counts.isEmpty) return null;

    // 가장 많이 쓴 조합을 고른다.
    final best = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
    final (category, code, className) = samples[best.key]!;

    return VendorSuggestion(
      expenseCategory: category,
      classCode: code,
      className: className,
      matchCount: best.value,
    );
  }

  /// 업체명 비교용 정규화. 공백·괄호 표기 차이로 못 찾는 걸 막는다.
  static String _normalize(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
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
    final res = await api.spreadsheets.values
        .get(spreadsheetId, "'$classSheet'!A2:B");
    final out = <int, String>{};
    for (final r in res.values ?? <List<Object?>>[]) {
      if (r.length < 2) continue;
      final code = int.tryParse('${r[0]}'.trim());
      if (code != null) out[code] = '${r[1]}'.trim();
    }
    return out;
  }
}
