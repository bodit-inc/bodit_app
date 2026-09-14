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

/// 비목 마스터. **하드코딩하지 않는다** — 시트에서 읽어 캐시한다.
///
/// 인가가 없으면 빈 목록을 준다(로그인 전 화면이 깨지지 않게).
final expenseCategoriesProvider = FutureProvider<List<String>>((ref) async {
  final client = await ref.watch(googleAuthProvider).authorizedClient(
        interactive: false,
      );
  if (client == null) return <String>[];
  return await ref.watch(masterDataRepositoryProvider).categories(client);
});

/// 분류코드 → 분류명. 시트에 수식을 안 두므로 앱이 이걸로 채운다.
final classNamesProvider = FutureProvider<Map<int, String>>((ref) async {
  final client = await ref.watch(googleAuthProvider).authorizedClient(
        interactive: false,
      );
  if (client == null) return <int, String>{};
  return await ref.watch(masterDataRepositoryProvider).classNames(client);
});
