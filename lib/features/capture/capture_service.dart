/// 증빙을 가져와 앱 저장소에 보관하고, OCR 에 보낼 수 있게 압축한다.
///
/// ## 원본은 지우지 않는다
///
/// 회계 자료라 서둘러 지울 이유가 없다. 촬영·선택한 파일을 앱 디렉토리로
/// **복사해두고** 그 경로를 큐에 넣는다. 갤러리 원본이 지워져도 전송이 살아남는다.
///
/// ## 압축은 비용 절감이다
///
/// Claude 이미지 토큰 ≈ (가로 × 세로) / 750. 긴 변을 1600px 로 줄이면
/// 장당 토큰이 눈에 띄게 준다. 영수증 글씨는 이 해상도면 충분히 읽힌다.
///
/// ## 회전은 보관할 때 픽셀에 굽는다
///
/// 세로로 들고 찍은 영수증이 Drive·Slack 미리보기에서 **왼쪽으로 90도**
/// 누워 보였다. 눌러서 열면 똑바로 보인다 — 이게 EXIF `Orientation` 의
/// 전형적인 증상이다. 카메라는 센서가 읽은 그대로(누운 채로) 픽셀을 저장하고
/// "보여줄 때 돌려라" 를 태그로만 적어둔다. 큰 이미지를 여는 뷰어는 그 태그를
/// 읽지만, 섬네일을 굽는 쪽은 자주 무시한다. 그래서 **같은 파일이 두 가지로
/// 보인다.**
///
/// 뷰어마다 다르게 보이는 걸 뷰어 쪽에서 고칠 방법은 없다. 그래서 보관하는
/// 순간 **태그가 말하는 각도로 픽셀을 실제로 돌리고 태그를 버린다.**
/// 그러면 돌릴지 말지 판단할 여지가 없어져 모든 뷰어가 같은 그림을 본다.
/// 세 목적지가 모두 이 파일을 쓰므로 한 곳만 고치면 Drive·Slack·OCR 이
/// 같이 똑바로 선다.
///
/// PNG 는 건드리지 않는다 — 카드 앱 캡처가 PNG 로 들어오는데 PNG 에는
/// `Orientation` 태그가 없어서 돌릴 것이 없고, 다시 인코딩하면 글씨만 상한다.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:bodit_app/core/log.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// 앱이 보관 중인 증빙 한 장.
class CapturedEvidence {
  const CapturedEvidence({required this.file, required this.isImage});

  final File file;

  /// PDF 는 OCR 로 바로 못 보낸다 — 이미지가 아니면 사용자가 직접 채운다.
  final bool isImage;
}

class CaptureService {
  const CaptureService();

  static const _uuid = Uuid();

  /// 카메라로 찍는다.
  Future<CapturedEvidence?> fromCamera() async {
    final shot = await ImagePicker().pickImage(
      source: ImageSource.camera,
      // 여기서 이미 줄여두면 뒤의 압축이 가볍다.
      maxWidth: 2400,
      imageQuality: 90,
    );
    if (shot == null) return null;
    return await _store(File(shot.path), isImage: true);
  }

  /// 갤러리에서 여러 장 고른다 — 시안 ⑥(다건)의 입구다.
  Future<List<CapturedEvidence>> fromGallery() async {
    final shots = await ImagePicker().pickMultiImage(
      maxWidth: 2400,
      imageQuality: 90,
    );
    final out = <CapturedEvidence>[];
    for (final s in shots) {
      out.add(await _store(File(s.path), isImage: true));
    }
    return out;
  }

  /// 파일에서 고른다. PDF 를 여기서 받는다.
  Future<List<CapturedEvidence>> fromFiles() async {
    // file_picker 13 에서 `FilePicker.platform` 이 없어지고 정적 메서드가 됐다.
    // `allowMultiple` 도 사라졌다 — 다중은 pickFiles, 단일은 pickFile 이다.
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['pdf', 'jpg', 'jpeg', 'png'],
    );

    final out = <CapturedEvidence>[];
    for (final f in picked) {
      final path = f.path;
      if (path == null) continue;
      final ext = p.extension(path).toLowerCase();
      out.add(await _store(File(path), isImage: ext != '.pdf'));
    }
    return out;
  }

  /// 앱 디렉토리로 복사한다. 원본이 사라져도 전송이 살아남게.
  ///
  /// JPEG 계열은 그냥 복사하지 않고 **회전을 픽셀에 굽는다**(위 설명 참조).
  /// 구우면 확장자가 `.jpg` 로 고정된다 — HEIC 로 들어와도 JPEG 으로 나간다.
  /// Drive 의 파일명 확장자가 이 경로에서 오므로 둘이 어긋나면 안 된다.
  Future<CapturedEvidence> _store(File source, {required bool isImage}) async {
    final dir = Directory(
      p.join((await getApplicationDocumentsDirectory()).path, 'evidence'),
    );
    if (!dir.existsSync()) await dir.create(recursive: true);

    final id = _uuid.v4();
    final ext = p.extension(source.path).toLowerCase();

    if (isImage && _hasExifOrientation(ext)) {
      final baked = await _bakeOrientation(source, p.join(dir.path, '$id.jpg'));
      if (baked != null) return CapturedEvidence(file: baked, isImage: true);
      // 실패하면 복사로 내려간다 — 증빙을 잃는 것이 누워 보이는 것보다 나쁘다.
      log.w('회전 보정에 실패했다. 원본을 그대로 보관한다: ${source.path}');
    }

    final dest = File(p.join(dir.path, '$id${p.extension(source.path)}'));
    await source.copy(dest.path);
    return CapturedEvidence(file: dest, isImage: isImage);
  }

  /// `Orientation` 태그를 가질 수 있는 확장자. PNG·PDF 는 해당 없다.
  static bool _hasExifOrientation(String ext) =>
      const <String>{'.jpg', '.jpeg', '.heic', '.heif'}.contains(ext);

  /// 태그가 말하는 각도로 픽셀을 돌려 [targetPath] 에 쓴다. 태그는 버린다.
  ///
  /// `autoCorrectionAngle` 이 돌리는 쪽이고 `keepExif: false` 가 버리는
  /// 쪽이다. **둘 다 필요하다** — 돌리고 태그를 남기면 태그를 읽는 뷰어가
  /// 한 번 더 돌려서 반대로 눕는다. 지금은 둘 다 패키지 기본값이지만 **그래도
  /// 적어둔다** — 이 함수가 존재하는 이유가 그 두 값이라서, 기본값이 바뀌면
  /// 아무 흔적 없이 버그가 돌아온다.
  ///
  /// 출력은 JPEG 품질 95(패키지 기본값)다. 형식을 따로 넘기지 않는 대신
  /// 대상 이름을 `.jpg` 로 준다 — 기본값이 JPEG 이 아니게 되면 패키지가
  /// 확장자 검사에서 던지고, 아래 catch 가 복사로 내려간다.
  ///
  /// 크기는 줄이지 않는다. 회계가 보관하는 원본이라 화질을 깎을 이유가 없고,
  /// 들어오는 사진은 이미 picker 가 2400px 로 제한했다.
  /// OCR 로 보낼 때의 축소는 [compressForOcr] 가 따로 한다.
  Future<File?> _bakeOrientation(File source, String targetPath) async {
    try {
      final out = await FlutterImageCompress.compressAndGetFile(
        source.absolute.path,
        targetPath,
        minWidth: 2400,
        minHeight: 2400,
        // ignore: avoid_redundant_argument_values — 위 설명 참조
        autoCorrectionAngle: true,
        // ignore: avoid_redundant_argument_values — 위 설명 참조
        keepExif: false,
      );
      if (out == null) return null;
      final file = File(out.path);
      return file.existsSync() && file.lengthSync() > 0 ? file : null;
    } on Object catch (e) {
      log.w('회전 보정 중 예외: $e');
      return null;
    }
  }

  /// OCR 로 보내기 직전에 줄인다. 실패하면 원본 바이트를 그대로 돌려준다 —
  /// 압축은 비용 최적화지 필수 단계가 아니다.
  Future<Uint8List> compressForOcr(File image) async {
    try {
      final out = await FlutterImageCompress.compressWithFile(
        image.absolute.path,
        minWidth: 1600,
        minHeight: 1600,
        quality: 82,
      );
      if (out != null && out.isNotEmpty) return out;
    } on Object {
      // 무시하고 원본으로 간다.
    }
    return await image.readAsBytes();
  }
}
