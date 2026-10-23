/// 분류 하나. 코드와 이름은 **항상 같이 다닌다.**
///
/// 코드만 들고 다니면 화면이 이름을 찾으려고 마스터를 또 읽어야 하고,
/// 이름만 들고 다니면 시트에 쓸 코드가 없다. 둘을 떼면 한쪽이 비는 순간이 생긴다.
library;

import 'package:flutter/foundation.dart';

@immutable
class ClassChoice {
  const ClassChoice({required this.code, required this.name});

  /// `_분류마스터` A열.
  final int code;

  /// `_분류마스터` B열. **마스터에서 푼 이름이다** —
  /// 다른 시트에 적힌 이름을 그대로 쓰지 않는다(아래 `CardInfo` 주석 참조).
  final String name;

  /// 칩에 그대로 쓴다. 코드를 같이 보여주는 건 회계 담당자가 코드로 말하기 때문이다.
  String get label => '$code $name';

  @override
  bool operator ==(Object other) =>
      other is ClassChoice && other.code == code && other.name == name;

  @override
  int get hashCode => Object.hash(code, name);

  @override
  String toString() => 'ClassChoice($label)';
}
