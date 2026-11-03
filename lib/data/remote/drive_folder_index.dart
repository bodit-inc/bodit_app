/// 월 폴더 ID 를 **시트에 적어두고 모두가 같은 폴더를 쓰게** 한다.
///
/// ## 왜 Drive 를 조회하지 않는가
///
/// 증빙은 소속일자의 **월**(`2608`)별 폴더에 들어간다. 그러면 "그 폴더가 이미
/// 있나?" 를 알아야 하는데, `drive.file` scope 의 `files.list` 는 **그 계정에서
/// 이 앱이 만든 파일만** 돌려준다(ADR Decision 5).
/// 다른 사람이 만들어둔 `2608` 은 조회에 안 잡히고 앱은 "없네" 하며 하나 더
/// 만든다 — 실제로 `2026-10` 이 두 개 생긴 적이 있다. 폴더를 회사 전체에
/// 공개해도 결과는 같다. 사람이 드라이브에서 찾을 수 있는 것과 앱이 API 로
/// 조회할 수 있는 것이 **다른 규칙**이라서다.
///
/// 폴더가 월 단위라 이 조회 문제는 전보다 **더** 아프다. 일자 폴더는 그 날
/// 처음 제출한 사람만 걸렸지만, 월 폴더는 한 달 내내 같은 한 칸을 공유한다 —
/// 기록이 어긋나면 그 달 증빙이 두 폴더로 갈린다.
///
/// 스코프를 `drive` 로 넓히면 조회는 되지만 앱이 그 사람 드라이브 전체를
/// 보게 된다 — ADR Decision 5 를 무효로 만드는 대가다. 그래서 **조회를
/// 포기하고 기록을 공유한다**: 먼저 제출한 사람이 폴더를 만들고 그 ID 를
/// 매입내역 시트의 `_드라이브폴더` 탭에 적는다. 뒤에 오는 사람은 Drive 에
/// 묻지 않고 그 행을 읽어 같은 폴더에 올린다.
///
/// `_비목마스터`·`_분류마스터` 를 읽는 것과 같은 패턴이다 — 앱이 알아야 하는
/// 공유 상태는 시트에 둔다(ADR: 시트가 원천).
///
/// ## 왜 남이 만든 폴더에 쓸 수 있는가
///
/// `drive.file` 로는 폴더를 **조회**할 수 없지만, 부모 ID 를 알고 사용자에게
/// 쓰기 권한이 있으면 그 안에 파일을 **만드는** 것은 된다.
/// `DRIVE_FOLDER_ID`(앱이 만들지 않은 폴더)에 지금까지 올려온 것이 그 증거다.
/// 그래서 ID 만 공유하면 충분하다.
///
/// ## 동시 제출이 겹치면 폴더가 둘 생길 수 있다
///
/// 두 사람이 같은 달을 거의 동시에 처음 제출하면, 둘 다 "기록이 없다" 를
/// 보고 각자 폴더를 만들어 각자 행을 적는다. 그래서 읽을 때는 **같은 연월의
/// 첫 행만** 쓴다 — 셋째 사람부터는 다시 한 폴더로 모인다.
/// 남은 폴더 하나는 사람이 드라이브에서 합치면 된다.
/// 막으려면 잠금이 필요하고, 잠금을 두려면 백엔드가 필요하다(ADR Decision 1).
///
/// ## 기록을 못 남긴 폴더 — 내가 만든 것은 찾아낸다
///
/// 위 "동시 제출" 은 **두 사람**이 겹친 경우다. 운영에서는 혼자서도 둘이
/// 생겼다: 2611 폴더가 Drive 에 있는데 앱이 2611 을 또 만들었다.
/// 폴더는 만들었지만 **시트 기록이 없는 상태**였기 때문이다 — 폴더를 만든
/// 응답을 받다가 연결이 끊겼거나(`Connection reset`), 기록 자체가 실패하면
/// 그렇게 된다.
///
/// 그래서 만들기 직전에 **내가 만든 폴더만** 한 번 조회한다
/// (`_findMyFolder`). `drive.file` 로 남의 폴더는 못 찾지만 내가 만든 것은
/// 찾을 수 있다 — 고아 폴더는 정확히 내가 만든 것이다. 시트 기록은 여전히
/// **사람들 사이**를 맞추는 장치고, 이 조회는 **내 뒷정리**다.
///
/// 기록에 실패했으면 그 사실도 들고 나간다(`takeRecordWarning`) —
/// 로그만 남기면 아무도 모르고, 그 달 증빙이 내내 두 폴더로 갈린다.
///
/// ## 실패하면 숨기지 않는다
///
/// 폴더를 못 정하면 예외를 던진다. 루트 폴더로 **조용히** 떨어지지 않는다 —
/// 그러면 사용자는 폴더가 생긴 줄 알고, 몇 달 뒤 회계가 루트에 섞인 파일을
/// 발견한다. 앱 입장에서는 Drive 목적지 하나가 실패한 것뿐이고, 시트 행과
/// Slack 글은 그대로 나간다(ADR Decision 4).
library;

import 'package:bodit_app/core/log.dart';
import 'package:bodit_app/core/utils/filename.dart';
import 'package:bodit_app/core/utils/retry.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/googleapis_auth.dart' as gapis;

/// Drive 의 폴더 MIME 타입. 이 값으로 만들면 폴더가 된다.
const _folderMime = 'application/vnd.google-apps.folder';

class DriveFolderIndex {
  DriveFolderIndex({
    required this.spreadsheetId,
    required this.rootFolderId,
    this.tabName = '_드라이브폴더',
  });

  /// 매입내역 스프레드시트. 폴더 기록도 여기 둔다 —
  /// 환경(dev/prod)마다 시트가 갈리므로 폴더 기록도 저절로 갈린다.
  final String spreadsheetId;

  /// 월 폴더들의 부모. `.env` 의 `DRIVE_FOLDER_ID` 다.
  final String rootFolderId;

  final String tabName;

  /// 이번 실행에서 이미 알아낸 연월 → 폴더 ID.
  ///
  /// 한 번 전송에 같은 달이 여러 건 들어오는 게 흔하다
  /// (여러 장 한 번에 찍어 건별로 제출). 캐시가 없으면 건마다 시트를 읽는다.
  /// 폴더가 월 단위가 되면서 이 캐시가 거의 항상 맞는다.
  final Map<String, String> _cache = <String, String>{};

  /// 폴더는 정했지만 **그 ID 를 시트에 적지 못한** 마지막 사유.
  ///
  /// 적지 못하면 다음 사람(또는 다음 실행)이 같은 달 폴더를 하나 더 만든다 —
  /// 그 달 증빙이 두 폴더로 갈린다. 로그에만 남기면 아무도 모르고, 그렇다고
  /// 던지면 이미 잘 만들어진 폴더에 **올릴 수 있는 증빙을 버리는 것**이라
  /// 더 나쁘다. 그래서 올리기는 하고 사유를 여기 남긴다 —
  /// [takeRecordWarning] 으로 꺼내 제출 목록에 적는다.
  String? _recordWarning;

  /// 쌓인 기록 실패 사유를 꺼내고 비운다. 없으면 null.
  ///
  /// 꺼내면서 비우는 이유: 다음 건에 지난 경고가 다시 붙으면 사용자는 같은
  /// 문제가 또 났다고 읽는다.
  String? takeRecordWarning() {
    final w = _recordWarning;
    _recordWarning = null;
    return w;
  }

  /// [belongDate] 가 속한 **달**의 폴더 ID 를 돌려준다. 없으면 만들고 시트에
  /// 적는다.
  ///
  /// 폴더 이름은 `YYMM`(`2608`)이고 파일명 접두는 `YYMMDD`(`260805_…`)다 —
  /// 일부러 다르다. 앞 두 자리가 같아서 폴더 `2608` 안의 파일은 접두가 폴더
  /// 이름으로 시작한다(`formatMonthForFolder` 주석).
  Future<String> folderFor({
    required gapis.AuthClient client,
    required DateTime belongDate,
  }) async {
    final name = formatMonthForFolder(belongDate);

    final cached = _cache[name];
    if (cached != null) return cached;

    // 읽기는 몇 번 보내도 안전하다 — 끊긴 것 때문에 폴더를 새로 만드는 쪽이
    // 훨씬 비싸다(그 달 증빙이 갈린다).
    final recorded = (await retryTransient(
      () => _readIndex(client),
      what: '월 폴더 기록 읽기($name)',
    ))[name];
    if (recorded != null) {
      _cache[name] = recorded;
      return recorded;
    }

    // 기록이 없다. 그래도 **내가 전에 만들어둔 폴더**는 있을 수 있다
    // (아래 "기록을 못 남긴 폴더" 참고). 그래서 바로 만들지 않고 먼저 찾는다.
    //
    // 찾기와 만들기를 **한 덩어리로** 감싸는 이유: 만들기가 응답을 받다가
    // 끊기면 서버에는 폴더가 생겨 있다. 다시 시도할 때 찾기가 먼저 돌아야
    // 그 폴더를 집어낸다 — 안 그러면 재시도가 바로 두 번째 폴더를 만든다.
    final folderId = await retryTransient(
      () async =>
          await _findMyFolder(client, name) ?? await _createFolder(client, name),
      what: '월 폴더($name)',
    );

    // 기록에 실패해도 폴더는 이미 있다. 올리는 것까지 막지 않는다 —
    // 증빙을 버리는 쪽이 폴더가 갈리는 쪽보다 나쁘다. 대신 조용히 넘기지
    // 않는다: 사유를 들고 있다가 제출 목록에 적는다(`takeRecordWarning`).
    try {
      // 같은 연월·같은 ID 를 두 줄 적는 것은 **해롭지 않다** — 읽을 때
      // 첫 줄만 쓰고 두 줄이 같은 폴더를 가리킨다. 매입내역 append 와 달라서
      // 여기는 다시 보내도 된다.
      await retryTransient(
        () => _record(client, name: name, folderId: folderId),
        what: '월 폴더 기록($name)',
      );
    } on Object catch (e) {
      log.w('폴더 ID 를 시트에 적지 못했다 ($name=$folderId): $e');
      _recordWarning =
          '월 폴더($name) 를 시트에 기록하지 못했습니다 — '
          '다음 제출이 같은 달 폴더를 하나 더 만들 수 있습니다.\n$e';
    }

    _cache[name] = folderId;
    return folderId;
  }

  /// **이 앱이 이 계정으로 만든** 월 폴더를 찾는다. 없으면 null.
  ///
  /// ## 조회를 포기했다더니 왜 조회하는가
  ///
  /// 위에서 "폴더를 조회하지 않는다" 고 한 것은 **남이 만든 폴더**를 찾을 수
  /// 없기 때문이다. `drive.file` scope 의 `files.list` 는 그 계정에서 이 앱이
  /// 만든 것만 돌려준다 — 그래서 남의 `2608` 은 안 잡히고, 그것만 믿으면
  /// 사용자마다 폴더가 하나씩 생긴다. 시트 기록이 그 문제를 푼다.
  ///
  /// 그런데 운영에서 **다른** 경우가 나왔다: 내가 2611 을 만들었는데 시트에
  /// 기록이 없어서, 같은 기기·같은 계정이 2611 을 또 만들었다. 기록이 없는
  /// 길은 둘이다 —
  ///
  /// 1. 폴더를 만든 응답을 받다가 연결이 끊겼다(그날의 `Connection reset`).
  ///    예외가 올라가면서 기록 단계까지 가지 못한다
  /// 2. 기록 자체가 실패했다([_recordWarning])
  ///
  /// 이 조회는 **정확히 그 고아 폴더만** 집어낸다. 내가 만든 것은 scope 안에
  /// 있으니까. 남의 폴더는 여전히 안 보이므로 시트 기록의 역할은 그대로다 —
  /// 이건 그걸 대신하는 게 아니라 **내 뒷정리**다.
  ///
  /// 못 찾으면(또는 조회가 실패하면) null 을 돌려주고 만들기로 간다 —
  /// 예전 동작이다. 뒷정리용 조회가 새로운 실패 지점이 되면 안 된다.
  Future<String?> _findMyFolder(gapis.AuthClient client, String name) async {
    final api = drive.DriveApi(client);
    try {
      final res = await api.files.list(
        // 이름이 같고, 루트 폴더 안이고, 폴더이고, 휴지통에 없는 것.
        // 이름에 작은따옴표가 들어갈 일은 없다(`YYMM`)지만 규칙은 지킨다.
        q:
            "name = '${name.replaceAll("'", r"\'")}' and "
            "'$rootFolderId' in parents and "
            "mimeType = '$_folderMime' and trashed = false",
        // 공유 드라이브에 있을 수 있다. 둘 다 켜야 걸린다.
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
        // 둘 이상 나오면 **먼저 만든 것**을 쓴다. 시트를 읽을 때 첫 줄을 쓰는
        // 것과 같은 규칙이라야 사람마다 다른 폴더로 갈리지 않는다.
        orderBy: 'createdTime',
        pageSize: 2,
        $fields: 'files(id,name)',
      );
      final found = res.files;
      if (found == null || found.isEmpty) return null;
      final id = found.first.id;
      if (id == null) return null;
      log.d('기록에 없지만 내가 만든 월 폴더를 찾았다: $name ($id)');
      return id;
    } on Object catch (e) {
      log.w('내가 만든 월 폴더를 조회하지 못했다 ($name): $e');
      return null;
    }
  }

  /// `_드라이브폴더` 탭을 읽어 연월 → 폴더 ID 로 만든다.
  ///
  /// **같은 연월이 여러 행이면 첫 행만** 쓴다(위 "동시 제출" 참고).
  ///
  /// 일자 폴더 시절의 행(`260805`)이 같은 탭에 남아 있어도 상관없다 —
  /// 이제 `2608` 로 찾으므로 그 행에는 닿지 않는다. 지우지 않는다: 그
  /// 폴더들에 이미 올라간 증빙이 어디 있었는지를 말해주는 기록이다.
  Future<Map<String, String>> _readIndex(gapis.AuthClient client) async {
    final api = sheets.SheetsApi(client);
    final sheets.ValueRange res;
    try {
      // 탭 이름은 작은따옴표로 감싼다 — 밑줄로 시작하거나 한글이 섞이면
      // 따옴표 없이는 A1 표기가 깨진다.
      res = await api.spreadsheets.values.get(spreadsheetId, "'$tabName'!A2:B");
    } on Object catch (e) {
      // 탭이 아직 없는 것뿐이면 "기록 없음" 과 같다 — `_record` 가 만든다.
      if (_isMissingTab(e)) return <String, String>{};
      rethrow;
    }

    return parseIndex(res.values ?? <List<Object?>>[]);
  }

  /// 읽어온 행들을 연월 → 폴더 ID 로 접는다.
  ///
  /// 네트워크를 타지 않게 따로 뺐다 — **같은 연월의 첫 행만 쓴다** 는 규칙이
  /// 이 기능의 핵심인데(위 "동시 제출" 참고), 그걸 손으로 확인할 수는 없다.
  static Map<String, String> parseIndex(List<List<Object?>> rows) {
    final out = <String, String>{};
    for (final row in rows) {
      if (row.length < 2) continue;
      final name = '${row[0]}'.trim();
      final id = '${row[1]}'.trim();
      if (name.isEmpty || id.isEmpty) continue;
      // putIfAbsent — 뒤에 온 중복 행은 버린다.
      out.putIfAbsent(name, () => id);
    }
    return out;
  }

  Future<String> _createFolder(gapis.AuthClient client, String name) async {
    final api = drive.DriveApi(client);
    final folder = await api.files.create(
      drive.File()
        ..name = name
        ..mimeType = _folderMime
        ..parents = <String>[rootFolderId],
      // 공유 드라이브에 쓰려면 반드시 켜야 한다. 안 켜면 404 가 난다.
      supportsAllDrives: true,
      $fields: 'id',
    );
    final id = folder.id;
    if (id == null) {
      throw StateError('월 폴더($name)를 만들었지만 ID 를 못 받았습니다.');
    }
    return id;
  }

  /// 연월 → 폴더 ID 한 줄을 붙인다. 탭이 없으면 만들고 머리글부터 넣는다.
  Future<void> _record(
    gapis.AuthClient client, {
    required String name,
    required String folderId,
  }) async {
    final api = sheets.SheetsApi(client);
    try {
      await _append(api, <Object>[name, folderId, _nowStamp()]);
    } on Object catch (e) {
      if (!_isMissingTab(e)) rethrow;
      await _createTab(api);
      await _append(api, <Object>['연월', '폴더ID', '만든시각']);
      await _append(api, <Object>[name, folderId, _nowStamp()]);
    }
  }

  Future<void> _append(sheets.SheetsApi api, List<Object> row) async {
    await api.spreadsheets.values.append(
      sheets.ValueRange(values: <List<Object>>[row]),
      spreadsheetId,
      "'$tabName'!A1",
      // RAW 로 넣는다 — 폴더 이름은 **글자 그대로**여야 한다. USER_ENTERED 로
      // 주면 시트가 `2608` 을 숫자로 해석하고, 그러면 앞에 0 이 오는 형식
      // (`0601`)에서 한 자리가 날아간다.
      valueInputOption: 'RAW',
      insertDataOption: 'INSERT_ROWS',
    );
  }

  /// 숨은 탭으로 만든다 — `_비목마스터` 처럼 회계 담당자가 볼 것이 아니다.
  Future<void> _createTab(sheets.SheetsApi api) async {
    try {
      await api.spreadsheets.batchUpdate(
        sheets.BatchUpdateSpreadsheetRequest(
          requests: <sheets.Request>[
            sheets.Request(
              addSheet: sheets.AddSheetRequest(
                properties: sheets.SheetProperties(
                  title: tabName,
                  hidden: true,
                ),
              ),
            ),
          ],
        ),
        spreadsheetId,
      );
    } on Object catch (e) {
      // 둘이 동시에 만들면 한쪽은 "이미 있다" 로 떨어진다. 그건 성공과 같다.
      if (_isDuplicateTab(e)) return;
      rethrow;
    }
  }

  /// 범위를 못 읽는 400 — 거의 항상 "그 탭이 없다" 다.
  ///
  /// Sheets API 는 탭이 없을 때 404 가 아니라 400 에 `Unable to parse range`
  /// 를 담아 보낸다. 다른 400(ID 가 스프레드시트가 아님 등)과 구분해야
  /// 엉뚱한 실패를 "탭 없음" 으로 삼키지 않는다.
  static bool _isMissingTab(Object e) =>
      e is sheets.DetailedApiRequestError &&
      e.status == 400 &&
      (e.message ?? '').contains('Unable to parse range');

  static bool _isDuplicateTab(Object e) =>
      e is sheets.DetailedApiRequestError &&
      e.status == 400 &&
      (e.message ?? '').contains('already exists');

  /// 기록용 시각. 사람이 읽을 것이라 로컬 시간으로 적는다.
  static String _nowStamp() => DateTime.now().toIso8601String();
}
