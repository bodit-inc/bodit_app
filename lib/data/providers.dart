/// 데이터 계층 provider 배선.
///
/// 화면은 여기 있는 provider 만 읽는다. 저장소를 직접 new 하지 않는다 —
/// 테스트에서 갈아끼우려면 한 곳에 모여 있어야 한다.
library;

import 'package:bodit_app/core/config.dart';
import 'package:bodit_app/core/log.dart';
import 'package:bodit_app/data/local/queue_db.dart';
import 'package:bodit_app/data/remote/drive_repository.dart';
import 'package:bodit_app/data/remote/google_auth.dart';
import 'package:bodit_app/data/remote/ocr_service.dart';
import 'package:bodit_app/data/remote/sheets_repository.dart';
import 'package:bodit_app/data/remote/slack_repository.dart';
import 'package:bodit_app/data/submission_sender.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:googleapis_auth/googleapis_auth.dart' as gapis;

/// Google 로그인·인가. **모든 저장소가 이걸 쓰므로 data 계층이 소유한다.**
/// 화면(`features/auth`)은 이 위에 로그인 상태를 얹을 뿐이다.
final googleAuthProvider = Provider<GoogleAuthService>((ref) {
  return GoogleAuthService();
});

final queueDbProvider = Provider<QueueDb>((ref) {
  final db = QueueDb();
  ref.onDispose(db.close);
  return db;
});

final driveRepositoryProvider = Provider<DriveRepository>((ref) {
  return DriveRepository(rootFolderId: Config.driveFolderId);
});

final sheetsRepositoryProvider = Provider<SheetsRepository>((ref) {
  return SheetsRepository(spreadsheetId: Config.spreadsheetId);
});

final masterDataRepositoryProvider = Provider<MasterDataRepository>((ref) {
  return MasterDataRepository(spreadsheetId: Config.spreadsheetId);
});

final slackRepositoryProvider = Provider<SlackRepository>((ref) {
  return SlackRepository(
    botToken: Config.slackBotToken,
    channelId: Config.slackChannelId,
    spreadsheetId: Config.spreadsheetId,
  );
});

final ocrServiceProvider = Provider<OcrService>((ref) {
  return OcrService(apiKey: Config.anthropicApiKey);
});

final submissionSenderProvider = Provider<SubmissionSender>((ref) {
  return SubmissionSender(
    db: ref.watch(queueDbProvider),
    auth: ref.watch(googleAuthProvider),
    drive: ref.watch(driveRepositoryProvider),
    sheets: ref.watch(sheetsRepositoryProvider),
    slack: ref.watch(slackRepositoryProvider),
  );
});

/// 전송 대기 목록. 홈과 내 제출 화면이 같이 본다.
final pendingSubmissionsProvider = StreamProvider<List<Submission>>((ref) {
  return ref.watch(queueDbProvider).watchAll();
});

/// 인가된 Google 클라이언트. 없으면 **왜 없는지 말하고 던진다.**
///
/// 예전엔 인가가 없을 때 빈 목록을 돌려줬는데, 그러면 화면이
/// "비목 마스터를 읽지 못했습니다" 만 띄우고 원인(로그인 안 됨 / 인가 거부 /
/// 시트 ID 오류 / 탭이 빔)을 구분해주지 못한다. 조용히 실패하면 안 된다.
Future<gapis.AuthClient> _requireClient(Ref ref) async {
  final auth = ref.watch(googleAuthProvider);
  if (!auth.isSignedIn) {
    throw StateError('로그인이 필요합니다.');
  }
  // 여기서 interactive 를 켠다 — 로그인 때 인가를 거부했거나 스코프가 늘어난
  // 경우에도 다시 물어볼 수 있어야 한다.
  //
  // 타임아웃을 건다. 네트워크나 플랫폼 채널이 응답하지 않으면 Future 가 영원히
  // 안 끝나고 화면은 스피너만 돈다 — 그건 "조용히 실패" 와 똑같이 나쁘다.
  log.d('인가 확인 시작');
  final client = await auth.authorizedClient().timeout(
    const Duration(seconds: 20),
    onTimeout: () => throw StateError(
      'Google 인가 확인이 20초 안에 끝나지 않았습니다.\n'
      '네트워크를 확인하고 다시 시도해 주세요.',
    ),
  );
  log.d('인가 확인 끝: ${client != null ? "OK" : "null"}');
  if (client == null) {
    throw StateError(
      'Google 시트·드라이브 접근 권한이 없습니다.\n'
      '로그아웃 후 다시 로그인하면서 동의해 주세요.',
    );
  }
  return client;
}

/// 비목 마스터. **하드코딩하지 않는다** — 시트에서 읽는다.
///
/// ## 성공만 캐시하고, 실패는 항상 다시 시도한다
///
/// `FutureProvider` 는 성공뿐 아니라 **에러도 캐시한다.** 그래서 한 번 실패하면
/// 시트를 다시 열어도 시도조차 하지 않고 지난 에러를 그대로 보여준다.
/// 설정을 고쳐도 앱을 껐다 켜야 반영됐다.
///
/// 그렇다고 매번 새로 읽으면, 잘 바뀌지도 않는 마스터를 팝업 열 때마다 받아온다.
///
/// 그래서 `autoDispose` + **성공 직전에만 `ref.keepAlive()`** 를 쓴다:
///
///   - 성공 → `keepAlive()` 로 캐시가 남는다. 다음에 열면 즉시 뜬다
///   - 실패 → `keepAlive()` 까지 못 가고 던진다. 시트가 닫히면 버려지고
///     다시 열 때 처음부터 읽는다
final FutureProvider<List<String>> expenseCategoriesProvider =
    FutureProvider.autoDispose<List<String>>((ref) async {
  final client = await _requireClient(ref);
  final master = ref.watch(masterDataRepositoryProvider);
  log.d('비목 마스터 읽기 시작 (sheet=${Config.spreadsheetId})');
  final list = await master.categories(client).timeout(
    const Duration(seconds: 20),
    onTimeout: () => throw StateError(
      '시트를 20초 안에 읽지 못했습니다.\n'
      'SPREADSHEET_ID 와 네트워크를 확인해 주세요.',
    ),
  );
  log.d('비목 마스터 읽기 끝: ${list.length}개');
  // 여기까지 와야 캐시한다. 위에서 던지면 캐시가 안 남고 다음에 다시 읽는다.
  ref.keepAlive();
  if (list.isEmpty) {
    // 여기까지 왔으면 인가·시트 접근은 성공했다. 탭이 비어 있는 것이다.
    throw StateError(
      '시트의 `_비목마스터` 탭이 비어 있습니다.\n'
      'A2 부터 비목을 한 줄에 하나씩 넣어주세요.',
    );
  }
  return list;
});

/// 분류코드 → 분류명. 시트에 수식을 안 두므로 앱이 이걸로 채운다.
///
/// 비목과 같은 규칙 — 성공만 캐시, 실패는 항상 재시도.
final FutureProvider<Map<int, String>> classNamesProvider =
    FutureProvider.autoDispose<Map<int, String>>((ref) async {
  final client = await _requireClient(ref);
  final map = await ref.watch(masterDataRepositoryProvider).classNames(client);
  ref.keepAlive();
  return map;
});
