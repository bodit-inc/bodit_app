/// 과거 이력에서 센 비목 하나와 그 건수.
///
/// **건수를 떼지 않는다.** 비목 후보는 "이 업체를 이렇게 처리한 적이 있다" 는
/// 말이고, 후보가 둘 이상일 때 사용자가 고를 근거는 **얼마나 자주** 그랬느냐
/// 뿐이다. 이름만 주면 4건짜리와 1건짜리가 똑같이 보인다.
library;

import 'package:flutter/foundation.dart';

@immutable
class CategoryTally {
  const CategoryTally({required this.category, required this.count});

  /// 매입내역 시트 E열(비목)에 적혀 있던 값. 마스터의 이름과 같아야 하지만
  /// **확인하지 않는다** — 과거 행을 그대로 읽은 것이고, 어긋났다면 그건
  /// 시트 쪽 사실이다.
  final String category;

  /// 이 업체를 이 비목으로 처리한 과거 건수.
  final int count;

  /// 칩에 그대로 쓴다. 건수가 곧 고를 근거라서 같이 적는다.
  String get label => '$category $count건';

  @override
  bool operator ==(Object other) =>
      other is CategoryTally &&
      other.category == category &&
      other.count == count;

  @override
  int get hashCode => Object.hash(category, count);

  @override
  String toString() => 'CategoryTally($label)';
}
