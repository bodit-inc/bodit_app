/// 증빙 파일을 Google Drive 에 올린다.
///
/// scope 는 `drive.file` 뿐이다 — **앱이 만든 파일만** 접근할 수 있다.
/// 남의 증빙을 읽거나 지우는 게 원천적으로 불가능하다(ADR Decision 5).
/// 대신 폴더를 **검색할 수 없으므로** 부모 폴더 ID 를 미리 알고 있어야 한다.
///
/// ## 증빙은 날짜 폴더 안에 들어간다
///
/// `DRIVE_FOLDER_ID` 바로 아래가 아니라 `소속일자`(`260805`) 폴더 안이다.
/// 폴더 이름은 파일명 접두와 같은 형식을 쓴다 — 어긋나면 `260805` 폴더에
/// `260806_…` 이 들어간 것처럼 보인다.
///
/// 한때는 하위 폴더를 아예 만들지 않았다. `drive.file` 로는 `files.list` 가
/// **그 계정에서 앱이 만든 파일만** 돌려줘서, 폴더를 "찾아서 없으면 만들게"
/// 하면 사용자마다 같은 이름 폴더가 하나씩 더 생겼기 때문이다(`2026-10` 이
/// 두 개 생겼다). 지금은 **찾지 않는다** — 먼저 만든 사람이 폴더 ID 를 시트에
/// 적고 나머지는 그걸 읽어 쓴다. 자세한 이유는 [DriveFolderIndex] 에 있다.
///
/// 폴더를 못 정하면 올리지 않고 던진다. 루트로 조용히 떨어지면 사용자는
/// 폴더가 생긴 줄 알고, 나중에 회계가 루트에 섞인 파일을 발견한다.
/// Drive 하나가 실패해도 시트 행과 Slack 글은 나간다(ADR Decision 4).
library;

import 'dart:io';

import 'package:bodit_app/data/remote/drive_folder_index.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/googleapis_auth.dart' as gapis;
import 'package:mime/mime.dart';

class DriveRepository {
  const DriveRepository({required this.folders});

  /// 날짜 폴더 ID 를 정해주는 쪽. 루트 폴더 ID 도 이쪽이 들고 있다 —
  /// 이 저장소는 "어느 폴더에 올릴지" 를 스스로 정하지 않는다.
  final DriveFolderIndex folders;

  /// 증빙을 올리고 파일 URL 을 돌려준다.
  ///
  /// [filename] 은 확장자를 뺀 이름이다 — 확장자는 원본에서 가져다 붙인다.
  /// 사용자가 검토 화면에서 고쳤을 수 있고, **치환 규칙은 이미 적용된 상태**로
  /// 들어온다고 가정한다(`sanitizeSegment`).
  ///
  /// [belongDate] 는 들어갈 날짜 폴더를 정한다. 파일명 접두와 **같은 날짜**를
  /// 넘겨야 한다 — 호출부가 둘을 따로 계산하면 갈라진다.
  Future<String> upload({
    required gapis.AuthClient client,
    required File source,
    required String filename,
    required DateTime belongDate,
  }) async {
    final api = drive.DriveApi(client);

    final parentId = await folders.folderFor(
      client: client,
      belongDate: belongDate,
    );

    final ext = source.path.contains('.') ? source.path.split('.').last : 'jpg';
    final mime = lookupMimeType(source.path) ?? 'application/octet-stream';
    final length = await source.length();

    final created = await api.files.create(
      drive.File()
        ..name = '$filename.$ext'
        ..parents = <String>[parentId],
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
