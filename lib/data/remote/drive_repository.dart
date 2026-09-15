/// 증빙 파일을 Google Drive 에 올린다.
///
/// scope 는 `drive.file` 뿐이다 — **앱이 만든 파일만** 접근할 수 있다.
/// 남의 증빙을 읽거나 지우는 게 원천적으로 불가능하다(ADR Decision 5).
/// 대신 폴더를 검색할 수도 없으므로 **폴더 ID 를 미리 알고 있어야 한다.**
library;

import 'dart:io';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/googleapis_auth.dart' as gapis;
import 'package:mime/mime.dart';

class DriveRepository {
  const DriveRepository({required this.rootFolderId});

  /// 증빙을 모아두는 공유 드라이브 폴더 ID.
  /// `drive.file` scope 로는 이 폴더를 조회할 수 없으므로 설정값으로 주입한다.
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
    required DateTime belongDate,
  }) async {
    final api = drive.DriveApi(client);
    final folderId = await _ensureMonthFolder(api, belongDate);

    final ext = source.path.contains('.') ? source.path.split('.').last : 'jpg';
    final mime = lookupMimeType(source.path) ?? 'application/octet-stream';
    final length = await source.length();

    final created = await api.files.create(
      drive.File()
        ..name = '$filename.$ext'
        ..parents = <String>[folderId],
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

  /// `[YYYY-MM]` 폴더를 찾거나 만든다.
  ///
  /// `drive.file` scope 로는 **앱이 만든 폴더만** 검색된다. 사람이 Drive 에서
  /// 직접 만든 같은 이름 폴더는 안 보이므로 앱이 하나 더 만들 수 있다.
  /// 폴더는 회계 담당자가 먼저 만들어두는 운영이라면, 그 ID 를 설정으로 받는 편이 낫다.
  Future<String> _ensureMonthFolder(drive.DriveApi api, DateTime d) async {
    final name = '${d.year}-${d.month.toString().padLeft(2, '0')}';
    final q =
        "name = '$name' and '$rootFolderId' in parents "
        "and mimeType = 'application/vnd.google-apps.folder' and trashed = false";

    final found = await api.files.list(
      q: q,
      supportsAllDrives: true,
      includeItemsFromAllDrives: true,
      $fields: 'files(id)',
    );
    final existing = found.files;
    if (existing != null && existing.isNotEmpty) return existing.first.id!;

    final created = await api.files.create(
      drive.File()
        ..name = name
        ..mimeType = 'application/vnd.google-apps.folder'
        ..parents = <String>[rootFolderId],
      supportsAllDrives: true,
      $fields: 'id',
    );
    return created.id!;
  }
}

class DriveException implements Exception {
  const DriveException(this.message);

  final String message;

  @override
  String toString() => message;
}
