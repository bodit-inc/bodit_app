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
library;

import 'dart:io';
import 'dart:typed_data';

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
  Future<CapturedEvidence> _store(File source, {required bool isImage}) async {
    final dir = Directory(
      p.join((await getApplicationDocumentsDirectory()).path, 'evidence'),
    );
    if (!dir.existsSync()) await dir.create(recursive: true);

    final dest = File(p.join(dir.path, '${_uuid.v4()}${p.extension(source.path)}'));
    await source.copy(dest.path);
    return CapturedEvidence(file: dest, isImage: isImage);
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
