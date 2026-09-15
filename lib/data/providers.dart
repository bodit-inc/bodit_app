/// 데이터 계층 provider 배선.
///
/// 화면은 여기 있는 provider 만 읽는다. 저장소를 직접 new 하지 않는다 —
/// 테스트에서 갈아끼우려면 한 곳에 모여 있어야 한다.
library;

import 'package:bodit_app/core/config.dart';
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
  final client = await auth.authorizedClient();
  if (client == null) {
    throw StateError(
      'Google 시트·드라이브 접근 권한이 없습니다.\n'
      '로그아웃 후 다시 로그인하면서 동의해 주세요.',
    );
  }
  return client;
}

/// 비목 마스터. **하드코딩하지 않는다** — 시트에서 읽어 캐시한다.
final expenseCategoriesProvider = FutureProvider<List<String>>((ref) async {
  final client = await _requireClient(ref);
  final list = await ref.watch(masterDataRepositoryProvider).categories(client);
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
final classNamesProvider = FutureProvider<Map<int, String>>((ref) async {
  final client = await _requireClient(ref);
  return await ref.watch(masterDataRepositoryProvider).classNames(client);
});
