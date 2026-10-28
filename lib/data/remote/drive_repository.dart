/// 증빙 파일을 Google Drive 에 올린다.
///
/// scope 는 `drive.file` 뿐이다 — **앱이 만든 파일만** 접근할 수 있다.
/// 남의 증빙을 읽거나 지우는 게 원천적으로 불가능하다(ADR Decision 5).
/// 대신 폴더를 검색할 수도 없으므로 **폴더 ID 를 미리 알고 있어야 한다.**
///
/// ## 월 폴더를 만들지 않는다 — 증빙은 설정된 폴더 한 곳에 모인다
///
/// 예전에는 `[YYYY-MM]` 폴더를 찾아서 없으면 만들었다. 그런데 `drive.file`
/// 에서 `files.list` 는 **그 계정에서 이 앱이 만든 파일만** 돌려준다.
/// 다른 사람이 만들어둔 `2026-10` 은 조회에 안 잡히고, 앱은 "없네" 하고 하나
/// 더 만든다 — 실제로 드라이브에 `2026-10` 이 두 개 생겼다.
/// 공유 설정으로는 안 풀린다. 사람이 드라이브에서 찾을 수 있는 것과 앱이
/// API 로 조회할 수 있는 것이 **다른 규칙**이라서, 폴더를 회사 전체에
/// 공개해도 조회 결과는 그대로다.
///
/// 남은 길은 셋이었고(스코프 넓히기 · 월 폴더 ID 를 설정으로 받기 · 월 폴더
/// 없애기) 세 번째를 골랐다:
///
///   - 스코프를 `drive` 로 넓히면 ADR Decision 5 가 무효가 된다 —
///     앱이 그 사람 드라이브 전체를 보게 된다
///   - 월 폴더 ID 를 `.env` 로 받으면 매달 재빌드·재배포다
///   - 폴더가 하나뿐이면 **조회할 일 자체가 없다.** 파일명이
///     `260805_…` 로 시작해 이름순이 곧 시간순이고, 드라이브 검색창에
///     `2608` 을 치면 그 달 것만 나온다
library;

import 'dart:io';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/googleapis_auth.dart' as gapis;
import 'package:mime/mime.dart';

class DriveRepository {
  const DriveRepository({required this.rootFolderId});

  /// 증빙을 모아두는 공유 드라이브 폴더 ID.
  /// `drive.file` scope 로는 이 폴더를 조회할 수 없으므로 설정값으로 주입한다.
  ///
  /// 증빙은 **전부 여기 바로** 들어간다 — 하위 폴더를 만들지 않는다(위 설명).
  final String rootFolderId;

  /// 증빙을 올리고 파일 URL 을 돌려준다.
  ///
  /// [filename] 은 확장자를 뺀 이름이다 — 확장자는 원본에서 가져다 붙인다.
  /// 사용자가 검토 화면에서 고쳤을 수 있고, **치환 규칙은 이미 적용된 상태**로
  /// 들어온다고 가정한다(`sanitizeSegment`).
  Future<String> upload({
    required gapis.AuthClient client,
    required File source,
    required String filename,
  }) async {
    final api = drive.DriveApi(client);

    final ext = source.path.contains('.') ? source.path.split('.').last : 'jpg';
    final mime = lookupMimeType(source.path) ?? 'application/octet-stream';
    final length = await source.length();

    final created = await api.files.create(
      drive.File()
        ..name = '$filename.$ext'
        ..parents = <String>[rootFolderId],
      uploadMedia: drive.Media(source.openRead(), length, contentType: mime),
      // 공유 드라이브에 쓰려면 반드시 켜야 한다. 안 켜면 404 가 난다.
      supportsAllDrives: true,
      $fields: 'id,webViewLink',
    );

    final link = created.webViewLink;
    if (link == null) {
      throw DriveException('업로드는 됐지만 링크를 못 받았습니다 (id=${created.id}).');
    }
    return link;
  }
}

class DriveException implements Exception {
  const DriveException(this.message);

  final String message;

  @override
  String toString() => message;
}
