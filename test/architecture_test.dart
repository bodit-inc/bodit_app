/// 계층 규칙을 테스트로 고정한다.
///
/// 의존 방향은 문서에 적어두면 반드시 새어나간다 — 실제로 두 군데가 이미
/// 깨져 있었다(`data → features`, `core → features`).
/// 사람이 지키는 규칙 대신 **깨지면 빨개지는 규칙**으로 바꾼다.
///
///   features  →  data  →  models
///       ↘        ↙
///         core
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `lib/` 아래 손으로 쓴 dart 파일만. 생성물은 규칙 대상이 아니다.
List<File> _sourceFiles() {
  return Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where(
        (f) => !f.path.endsWith('.g.dart') && !f.path.endsWith('.freezed.dart'),
      )
      .toList();
}

/// 그 파일이 import 하는 우리 프로젝트 경로들.
List<String> _internalImports(File f) {
  final re = RegExp(r"import 'package:bodit_app/([^']+)'");
  return re
      .allMatches(f.readAsStringSync())
      .map((m) => m.group(1)!)
      .toList();
}

/// `lib/` 기준 상대 경로의 첫 조각. 최상위 파일은 `<root>`.
String _layerOf(String relative) {
  final parts = relative.split('/');
  return parts.length == 1 ? '<root>' : parts.first;
}

void main() {
  final files = _sourceFiles();

  test('소스 파일이 실제로 잡혀야 한다 (탐색 자체가 깨졌는지 확인)', () {
    expect(files.length, greaterThan(15));
  });

  test('models 는 바깥을 모른다 — core 외에 아무것도 import 하지 않는다', () {
    for (final f in files.where((f) => f.path.startsWith('lib/models/'))) {
      for (final imp in _internalImports(f)) {
        expect(
          _layerOf(imp),
          anyOf('models', 'core'),
          reason: '${f.path} → $imp\n'
              'models 는 도메인 타입이라 data·features 를 알면 안 된다. '
              '테스트가 목킹 없이 도는 이유가 이거다.',
        );
      }
    }
  });

  test('data 는 features 를 모른다 — 의존이 거꾸로 흐르면 안 된다', () {
    for (final f in files.where((f) => f.path.startsWith('lib/data/'))) {
      for (final imp in _internalImports(f)) {
        expect(
          _layerOf(imp),
          isNot('features'),
          reason: '${f.path} → $imp\n'
              '화면이 저장소를 쓰는 것이지 그 반대가 아니다. '
              '모든 저장소가 쓰는 자원이라면 그건 data 소유여야 한다 '
              '(googleAuthProvider 가 그래서 여기로 내려왔다).',
        );
      }
    }
  });

  test('core 는 features·data 를 모른다 — 기능을 모르는 층이다', () {
    for (final f in files.where((f) => f.path.startsWith('lib/core/'))) {
      for (final imp in _internalImports(f)) {
        expect(
          _layerOf(imp),
          anyOf('core', 'models'),
          reason: '${f.path} → $imp\n'
              'core 는 어디서나 쓰는 것만 담는다. 화면을 알아야 하는 것'
              '(라우터 같은)은 core 가 아니라 앱 조립 계층에 둔다.',
        );
      }
    }
  });

  test('화면은 저장소를 직접 만들지 않는다 — providers 를 통해 받는다', () {
    final banned = RegExp(
      r'\b(SheetsRepository|DriveRepository|SlackRepository|OcrService|QueueDb)\(',
    );
    for (final f in files.where((f) => f.path.startsWith('lib/features/'))) {
      expect(
        banned.hasMatch(f.readAsStringSync()),
        isFalse,
        reason: '${f.path} 가 저장소를 직접 생성한다.\n'
            'providers.dart 를 통해 받아야 테스트에서 갈아끼울 수 있다.',
      );
    }
  });
}
