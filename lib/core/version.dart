/// 버전 하나. **비교할 수 있다.**
///
/// ## 왜 문자열 비교로는 안 되나
///
/// `'1.0.10' < '1.0.9'` 다 — 사전순으로는 `1` 이 `9` 보다 작다. 그래서 자리마다
/// 숫자로 끊어 비교한다. 자리 수가 다르면(`1.0` ↔ `1.0.0`) 빠진 자리를 0 으로
/// 채운다.
///
/// ## 빌드 번호(`+5`)까지 본다
///
/// TestFlight·App Distribution 은 **버전 이름을 그대로 두고 빌드만 올리는**
/// 일이 흔하다 — `1.0.0+5` 다음이 `1.0.0+6` 이다. 빌드 번호를 안 보면 그
/// 올림이 "새 버전" 으로 안 잡히고, 그게 이 기능을 쓰는 가장 흔한 경우다.
///
/// ## 한쪽에 빌드 번호가 없으면 비교하지 않는다
///
/// Remote Config 에 `1.0.1` 만 적는 일이 생긴다. 그 빈자리를 0 으로 치면
/// `1.0.1+3` 을 쓰는 사람에게 "더 낮은 버전" 이라고 말하게 된다 — 적지 않은
/// 것은 "0" 이 아니라 "모른다" 다. 그래서 둘 다 적혀 있을 때만 빌드 번호로
/// 가른다.
library;

// @immutable 은 foundation 이 재수출한다 — meta 를 직접 의존하지 않는다.
import 'package:flutter/foundation.dart';

/// `1.0.0+5` 꼴의 버전. [tryParse] 로 만든다.
@immutable
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.name, [this.build]);

  /// 점으로 끊은 버전 이름. `1.0.0` → `[1, 0, 0]`.
  final List<int> name;

  /// `+` 뒤의 빌드 번호. **없으면 null 이다** — 0 과 다르다(위 주석).
  final int? build;

  /// 못 읽으면 **null 을 돌려준다.** 던지지 않는다.
  ///
  /// 원격에서 온 값(`latest_version`)도 이걸로 읽는데, 거기 오타 하나로
  /// 예외가 나면 업데이트 안내가 아니라 앱이 죽는다. 읽을 수 없는 값은
  /// "비교할 수 없다" 로 끝낸다.
  ///
  /// 받아주는 형태: `1.0.0+5` · `1.0.0` · `1.0` · `v1.0.0` · 앞뒤 공백.
  static AppVersion? tryParse(String? raw) {
    if (raw == null) return null;
    var text = raw.trim();
    if (text.isEmpty) return null;
    // `v1.0.0` 처럼 쓰는 사람이 있다. 원격 값은 사람이 콘솔에서 손으로 적는다.
    if (text.startsWith('v') || text.startsWith('V')) {
      text = text.substring(1);
    }

    // `1.0.0 (5)` — `AppInfo` 가 **화면에 보여주려고** 만든 표기다.
    // 그 문자열이 여기로 흘러들 수 있어서 같이 받아준다.
    final display = RegExp(r'^([\d.]+)\s*\((\d+)\)$').firstMatch(text);
    if (display != null) {
      text = '${display.group(1)}+${display.group(2)}';
    }

    final plus = text.split('+');
    if (plus.length > 2) return null;

    final parts = plus.first.split('.');
    final numbers = <int>[];
    for (final p in parts) {
      final n = int.tryParse(p.trim());
      // 한 자리라도 숫자가 아니면 버린다 — `1.0.0-beta` 같은 것을 반쯤 읽어
      // 비교에 쓰면 조용히 틀린 답이 나온다.
      if (n == null || n < 0) return null;
      numbers.add(n);
    }
    if (numbers.isEmpty) return null;

    int? build;
    if (plus.length == 2) {
      build = int.tryParse(plus[1].trim());
      if (build == null || build < 0) return null;
    }
    return AppVersion(numbers, build);
  }

  @override
  int compareTo(AppVersion other) {
    final len = name.length > other.name.length ? name.length : other.name.length;
    for (var i = 0; i < len; i++) {
      // 빠진 자리는 0 — `1.0` 과 `1.0.0` 은 같은 버전이다.
      final a = i < name.length ? name[i] : 0;
      final b = i < other.name.length ? other.name[i] : 0;
      if (a != b) return a.compareTo(b);
    }
    // 이름이 같다. 둘 다 빌드 번호가 적혀 있을 때만 그걸로 가른다.
    final mine = build;
    final theirs = other.build;
    if (mine == null || theirs == null) return 0;
    return mine.compareTo(theirs);
  }

  /// 이 버전이 [other] 보다 낮은가. "업데이트가 있다" 가 곧 이 질문이다.
  bool isOlderThan(AppVersion other) => compareTo(other) < 0;

  /// 사람이 읽을 표기. `1.0.0+5`, 빌드 번호가 없으면 `1.0.0`.
  @override
  String toString() => build == null
      ? name.join('.')
      : '${name.join('.')}+$build';

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0 && build == other.build;

  @override
  int get hashCode => Object.hash(name.join('.'), build);
}
