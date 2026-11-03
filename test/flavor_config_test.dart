/// 두 환경의 설정 키가 어긋나지 않게 고정한다.
///
/// 설정값이 늘어날 때 **네 군데**를 같이 고쳐야 한다:
/// `.env.dev.example` · `.env.prod.example` · `env_dev.dart` · `env_prod.dart`.
/// 한 군데를 빠뜨리면 그 환경에서만 build_runner 가 깨지거나(값 없음),
/// 더 나쁘게는 **한쪽 환경만 값이 비어서** 런타임에 조용히 틀린다.
///
/// 사람이 네 곳을 맞추는 대신 깨지면 빨개지게 한다.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `.env` 형식 파일에서 키만 뽑는다. 주석(`#`)과 빈 줄은 버린다.
Set<String> _envKeys(String path) {
  return File(path)
      .readAsLinesSync()
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('#') && l.contains('='))
      .map((l) => l.split('=').first)
      .toSet();
}

/// envied 클래스가 선언한 `varName:` 들.
Set<String> _declaredVarNames(String path) {
  final src = File(path).readAsStringSync();
  return RegExp("varName: '([^']+)'")
      .allMatches(src)
      .map((m) => m.group(1)!)
      .toSet();
}

void main() {
  const devExample = '.env.dev.example';
  const prodExample = '.env.prod.example';
  const devClass = 'lib/core/env/env_dev.dart';
  const prodClass = 'lib/core/env/env_prod.dart';

  test('예제 파일이 실제로 읽혀야 한다 (탐색 자체가 깨졌는지 확인)', () {
    expect(_envKeys(devExample).length, greaterThan(5));
    expect(_envKeys(prodExample).length, greaterThan(5));
  });

  test('두 예제 파일의 키가 같아야 한다', () {
    expect(
      _envKeys(devExample),
      equals(_envKeys(prodExample)),
      reason:
          '$devExample 과 $prodExample 의 키가 다릅니다.\n'
          '한쪽에만 키를 추가하면 그 환경만 빌드가 깨지거나, 더 나쁘게는 '
          '다른 환경에서 값이 비어 런타임에 조용히 틀립니다.',
    );
  });

  test('envied 클래스가 예제 파일의 키를 전부 선언해야 한다', () {
    for (final (klass, example) in [
      (devClass, devExample),
      (prodClass, prodExample),
    ]) {
      expect(
        _declaredVarNames(klass),
        equals(_envKeys(example)),
        reason:
            '$klass 가 선언한 키와 $example 의 키가 다릅니다.\n'
            '예제에만 있는 키는 아무도 읽지 않고, 클래스에만 있는 키는 '
            'build_runner 가 "값이 없다" 며 실패합니다.',
      );
    }
  });

  test('두 envied 클래스가 같은 필드를 가져야 한다', () {
    expect(
      _declaredVarNames(devClass),
      equals(_declaredVarNames(prodClass)),
      reason:
          'env_dev 와 env_prod 의 필드가 다릅니다.\n'
          'Config 는 둘을 짝지어 고르므로(`_pick`) 한쪽에만 있으면 컴파일되지 '
          '않거나, 그 환경에서만 설정이 빠집니다.',
    );
  });
}
