/// 매입내역 시트 읽기·쓰기.
///
/// 컬럼 계약의 단일 원천은 위키다:
///   ~/llm-wiki-template/wiki/projects/bodit-app/sheet-schema.md
///
/// **원칙은 append 다.** 기존 행을 고치거나 지우지 않는다(ADR Decision 2).
/// 그래서 행을 지목할 일이 없고 UUID 키 컬럼도 없다.
/// 읽기는 한다 — 비목·분류코드 추천을 위해 과거 행을 **읽는** 것은 예외가 아니다.
///
/// 쓰기 쪽 예외가 **하나** 있다: [SheetsRepository.fillEvidenceLink].
/// Drive 가 나중에 성공했을 때 그 행의 **증빙링크 칸만** 채운다. 키 컬럼이
/// 없으므로 append 가 돌려준 자리를 들고 있다가, 쓰기 전에 그 행이 여전히
/// 우리 행인지 확인한다. 왜 열었고 무엇을 확인하는지는 그 함수 주석에 있다.
library;

import 'package:bodit_app/data/remote/card_repository.dart';
import 'package:bodit_app/models/category_tally.dart';
import 'package:bodit_app/models/sheet_row.dart';
import 'package:flutter/foundation.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/googleapis_auth.dart' as gapis;

/// 과거 이력에서 뽑은 **비목** 추천. 근거를 같이 들고 다닌다 —
/// 근거 없이 채워두면 사용자가 못 믿고 전부 다시 확인한다.
///
/// **분류는 여기서 제안하지 않는다.** 예전엔 `classCode`·`className` 도 같이
/// 들고 있었지만 아무도 읽지 않았다 — 어느 예산으로 집행됐는지는 긁은 카드가
/// 이미 정해놨고(`CardDirectory`), 업체 이력은 거기에 할 말이 없다.
/// 들고만 있으면 언젠가 누가 쓴다.
@immutable
class VendorSuggestion {
  const VendorSuggestion({
    required this.categoryTallies,
    required this.totalCount,
    this.recentDescriptions = const <String>[],
  }) : assert(categoryTallies.length > 0, '후보가 없으면 추천이 아니다');

  /// 이 업체를 어떤 비목으로 처리했는지, **건수 많은 것부터.**
  ///
  /// 하나로 줄여서 돌려주지 않는다. 이력이 갈린 업체가 실제로 있고(문고에서
  /// 책도 사고 간식도 산다), 그때 1등만 보여주면 사용자는 나머지가 있었다는
  /// 사실조차 모른 채 추천을 그대로 제출한다.
  final List<CategoryTally> categoryTallies;

  /// 업체명이 맞은 과거 행 수. 1등의 건수가 아니라 **전체**다 —
  /// "7건 중 4건" 의 7.
  final int totalCount;

  /// 이 업체로 과거에 쓴 **내역** 들. 최근 것부터, 중복 제거.
  ///
  /// **자동으로 채우지 않는다.** 비목과 성격이 다르다 —
  /// 비목은 업체가 정해지면 거의 안 바뀌지만("영풍문고 = 도서인쇄비"),
  /// 내역은 건마다 달라진다("8월 도서" → "9월 도서").
  /// 지난 값을 자동으로 넣으면 **9월에 8월 도서가 조용히 들어간다.**
  /// 그래서 후보로만 보여주고 고르는 건 사용자가 한다.
  final List<String> recentDescriptions;

  /// 화면에 채워 넣을 비목. 가장 많이 쓴 것.
  String get expenseCategory => categoryTallies.first.category;

  /// 그 비목으로 처리한 건수. [totalCount] 와 같으면 이력이 갈리지 않았다는 뜻이다.
  int get matchCount => categoryTallies.first.count;

  /// 추천의 근거 문구. **"모두" 를 함부로 쓰지 않는다.**
  ///
  /// 예전에는 이력이 갈려도 "N건 모두" 로 적었다. 도서인쇄비 4건 + 복리후생비
  /// 3건인 업체에 "지난 4건 모두 도서인쇄비였습니다" 가 떴다 — 7건 중 4건인데
  /// 전부라고 말하고, 나머지 3건은 화면에서 사라졌다. 확인이 **가장 필요한
  /// 건**에 가장 확신 있는 문구가 나간 셈이다.
  ///
  /// **마침표로 끝낸다.** 분류 근거(`classReason`)는 "카드 3927 · 법인(신용)"
  /// 처럼 라벨이라 마침표가 없지만, 이쪽은 완결된 문장이다.
  String get reason => categoryTallies.length == 1
      ? '$totalCount건 모두 $expenseCategory였습니다.'
      : '$totalCount건 중 $matchCount건이 $expenseCategory였습니다.';

  /// 시트 행들로 추천을 만든다. **순수 함수다** — 네트워크 없이 테스트한다.
  ///
  /// 행 모양은 [SheetsRepository.lookupForVendor] 가 읽는 범위와 같다:
  /// `E 비목 · F 내역 · G 업체명 · H 분류코드 · I 분류명`.
  /// 비목이 비었거나 분류코드가 숫자가 아닌 행은 **아직 완성되지 않은 행**이라
  /// 세지 않는다 — 그런 행을 근거로 추천하면 사용자가 못 믿는다.
  static VendorSuggestion? fromRows(
    List<List<Object?>> rows, {
    required String vendor,
  }) {
    final needle = _squash(vendor);
    if (needle.isEmpty) return null;

    // 비목별 건수. **조합(비목+분류코드)이 아니라 비목으로 센다** —
    // 조합으로 세면 같은 비목이 분류코드 둘로 쪼개져서, 합이 더 많은 비목이
    // 1등을 놓친다(도서인쇄비 3+2건 vs 복리후생비 4건 → 4건짜리가 1등).
    // 분류는 어차피 카드가 정하므로 여기서 쪼갤 이유가 없다.
    final counts = <String, int>{};
    // 내역은 세지 않고 **등장 순서**대로 모은다 — 시트가 append-only 라
    // 뒤에 있는 게 최근이다. LinkedHashMap 의 삽입 순서로 중복을 지운다.
    final descriptions = <String, void>{};
    var total = 0;

    for (final row in rows) {
      // 완성되지 않은 행을 거르는 규칙은 **한 곳에 둔다** — 추측
      // ([CategoryGuess])도 같은 행을 보므로, 두 벌로 두면 한쪽만 고쳐진다.
      if (!_isUsableRow(row)) continue;
      if (_squash('${row[2]}') != needle) continue;

      final category = '${row[0]}'.trim();

      total++;
      counts[category] = (counts[category] ?? 0) + 1;

      final desc = '${row[1]}'.trim();
      if (desc.isNotEmpty) {
        // 다시 넣어 최신 등장 위치로 끌어올린다.
        descriptions.remove(desc);
        descriptions[desc] = null;
      }
    }

    if (counts.isEmpty) return null;

    return VendorSuggestion(
      categoryTallies: _rankCategories(counts),
      totalCount: total,
      // 최근 것부터 최대 6개. 더 보여주면 고르는 게 일이 된다.
      recentDescriptions: descriptions.keys.toList().reversed.take(6).toList(),
    );
  }

}

/// 과거 행 하나가 **추천의 근거로 쓸 만한지.**
///
/// 비목이 비었거나 분류코드가 숫자가 아닌 행은 아직 완성되지 않은 행이다 —
/// 그런 행을 근거로 "지난 3건이 도서인쇄비였습니다" 라고 말하면 사용자가
/// 한 번 확인해보고 다시는 추천을 믿지 않는다.
///
/// 범위는 `E2:I` 다: `E 비목 · F 내역 · G 업체명 · H 분류코드 · I 분류명`.
bool _isUsableRow(List<Object?> row) {
  if (row.length < 5) return false;
  if ('${row[0]}'.trim().isEmpty) return false;
  return int.tryParse('${row[3]}'.trim()) != null;
}

/// 글자 비교용 정규화. 공백·대소문자 표기 차이로 못 찾는 걸 막는다.
String _squash(String s) =>
    s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

/// 비목별 건수를 **많은 것부터** 세운다.
///
/// 동률은 **먼저 나온 쪽이 먼저다.** `List.sort` 는 안정 정렬이 아니라서
/// 그냥 두면 같은 시트를 읽을 때마다 칩 순서가 바뀐다 — 사용자는 앱이
/// 추천을 바꿨다고 읽는다.
///
/// [counts] 는 **등장 순서대로** 넣은 맵이어야 한다(Dart 의 기본 Map 은
/// 삽입 순서를 지킨다). 그 순서가 곧 동률의 기준이다.
List<CategoryTally> _rankCategories(Map<String, int> counts, {int? limit}) {
  final seen = counts.keys.toList();
  final ranked =
      counts.entries
          .map((e) => CategoryTally(category: e.key, count: e.value))
          .toList()
        ..sort((a, b) {
          final byCount = b.count.compareTo(a.count);
          if (byCount != 0) return byCount;
          return seen.indexOf(a.category).compareTo(seen.indexOf(b.category));
        });
  return limit == null ? ranked : ranked.take(limit).toList();
}

/// 받침에 맞는 주격 조사. `'도서' 가` · `'책상' 이`.
///
/// 근거 문구에 **OCR 이 읽은 말이 그대로 박힌다.** 조사를 하나로 고정하면
/// 둘 중 한쪽은 늘 틀린 한국어가 되고, 그 문구는 사용자가 "왜 이 비목이
/// 떴는지" 를 판단하는 유일한 근거다.
///
/// 한글 음절은 `(코드 - 0xAC00) % 28` 이 0 일 때 받침이 없다. 한글이 아닌
/// 글자(숫자·영문)로 끝나면 읽는 방법이 사람마다 달라서 `이` 로 둔다 —
/// 괄호로 감싼 말 뒤라 어느 쪽이든 읽을 수 있다.
String _subjectParticle(String word) {
  if (word.isEmpty) return '이';
  final c = word.codeUnitAt(word.length - 1);
  if (c < 0xAC00 || c > 0xD7A3) return '이';
  return (c - 0xAC00) % 28 == 0 ? '가' : '이';
}

/// OCR 이 읽은 값으로 비목을 **추측한** 것. 업체명이 정확히 맞는 과거 이력이
/// 없을 때의 차선책이다.
///
/// [VendorSuggestion] 과 성격이 다르다. 그쪽은 "이 업체를 지난 6건 모두
/// 도서인쇄비로 처리했다" 는 **기록**이라 칸을 채워도 된다. 이쪽은 업체명이
/// 비슷하거나 내역에 같은 말이 들어간 행을 긁어모은 **짐작**이라 칸을 채우지
/// 않는다 — 칩으로 띄워서 사용자가 고르게 한다.
///
/// 그래서 근거를 같이 들고 다닌다. "그나마 이거일 것 같다" 는 말은 왜 그렇게
/// 보였는지를 같이 말해주지 않으면 사용자가 판단할 수 없다.
@immutable
class CategoryGuess {
  const CategoryGuess({
    required this.tallies,
    required this.reason,
    this.recentDescriptions = const <String>[],
  }) : assert(tallies.length > 0, '후보가 없으면 추측이 아니다');

  /// 후보 비목들, 근거 건수가 많은 것부터. 최대 [maxCandidates] 개.
  final List<CategoryTally> tallies;

  /// 왜 이 후보들이 떴는지. 화면이 칩 아래에 그대로 보여준다.
  final String reason;

  /// **비슷한 업체로** 과거에 쓴 내역들. 최근 것부터, 중복 제거.
  ///
  /// 업체명이 비슷해서 걸린 경우에만 채운다. **내역이 겹쳐서 걸린 경우는
  /// 비운다** — 그때 걸린 행은 남의 가게 것이고, 내역은 "이 건에 무엇을
  /// 샀나" 라서 다른 가게의 문구를 후보로 주면 틀린 내역을 권하는 셈이다.
  /// 비목은 가게가 달라도 같을 수 있지만(도서는 어디서 사도 도서인쇄비)
  /// 내역은 그렇지 않다.
  ///
  /// [VendorSuggestion.recentDescriptions] 와 같은 성격이다 —
  /// **자동으로 채우지 않는다.** 내역은 건마다 달라서("8월 도서" →
  /// "9월 도서") 지난 값을 넣으면 9월에 8월 것이 조용히 들어간다.
  final List<String> recentDescriptions;

  /// 내역 후보 수의 상한. 더 보여주면 고르는 게 일이 된다
  /// (`VendorSuggestion` 과 같은 6개).
  static const _maxDescriptions = 6;

  /// 칩으로 띄울 후보 수의 상한.
  ///
  /// 셋을 넘기면 "그나마 이거일 것 같은 것" 이 아니라 **짧은 목록**이 된다.
  /// 그러면 아래 전체 목록과 하는 일이 같아지고, 사용자는 둘 중 어디서
  /// 골라야 하는지 헷갈린다.
  static const maxCandidates = 3;

  /// 두 업체명이 **같은 가게로 보이는지.**
  ///
  /// 두 가지로 본다:
  ///
  ///   - 한쪽이 다른 쪽을 품는다 — `영풍문고` ↔ `영풍문고 종로점`
  ///   - **앞머리가 세 글자 이상 같다** — `영풍문고 종로점` ↔ `영풍문고 강남점`.
  ///     양쪽에 지점명이 붙으면 서로 품지 않아서 품기만으로는 못 걸린다.
  ///     영수증마다 지점이 다른 가게(편의점·문고·카페)가 바로 그 경우다
  ///
  /// 앞머리를 **세 글자**로 끊은 이유: 두 글자면 `서울우유` 와 `서울식당` 이
  /// 같은 가게가 된다. 앞 세 글자가 같고 뒤가 다른 **남의 가게**는 드물다.
  ///
  /// 두 글자 미만은 아예 보지 않는다 — 한 글자가 들어간 업체명은 수십 개가
  /// 걸려서, 그건 추측이 아니라 소음이다.
  static bool similarVendor(String a, String b) {
    final x = _squash(a);
    final y = _squash(b);
    if (x.length < 2 || y.length < 2) return false;
    if (x.contains(y) || y.contains(x)) return true;

    var same = 0;
    while (same < x.length &&
        same < y.length &&
        x.codeUnitAt(same) == y.codeUnitAt(same)) {
      same++;
    }
    return same >= _minPrefix;
  }

  static const _minPrefix = 3;

  /// 과거 행에서 추측을 만든다. **순수 함수다** — 네트워크 없이 테스트한다.
  ///
  /// 근거를 **센 것이 아니라 고른다.** 두 신호를 섞지 않고 강한 쪽 하나만
  /// 쓴다:
  ///
  ///   1. **업체명이 비슷한 과거 행** — `영풍문고 종로점` 과 `영풍문고` 는
  ///      같은 가게다. 정확히 맞는 행이 없어서 추천이 비었을 뿐이다
  ///   2. **내역에 같은 말이 들어간 과거 행** — 업체가 처음이어도
  ///      `9월 도서` 는 과거의 `8월 도서` 와 같은 비목일 가능성이 높다
  ///
  /// 섞어서 한 번에 세면 안 된다. 1번은 거의 같은 가게이고 2번은 말이
  /// 겹친 것뿐인데, 합치면 2번 행이 많은 비목이 1번을 밀어낸다 —
  /// 근거 문구도 둘 중 무엇이라고 말할 수 없게 된다.
  static CategoryGuess? fromRows(
    List<List<Object?>> rows, {
    String? vendor,
    String? description,
  }) {
    final usable = rows.where(_isUsableRow).toList();
    if (usable.isEmpty) return null;

    // ── 1. 업체명이 비슷한 행 ──────────────────────────────────────
    //
    // 판정은 [similarVendor] 하나다. 지점명만 다른 가게가 여기서 걸린다.
    final needle = vendor ?? '';
    if (_squash(needle).length >= 2) {
      final counts = <String, int>{};
      // **내역도 같이 모은다.** 같은 가게에서 전에 무엇을 샀는지는 이 건의
      // 내역 후보이기도 하다 — 업체명이 정확히 맞을 때
      // ([VendorSuggestion.recentDescriptions]) 해주던 일을, 지점명이 달라
      // 못 맞은 건에도 해준다. 예전엔 그 건에서 내역 칸이 통째로 비었다.
      final descriptions = <String, void>{};
      var matched = 0;
      for (final row in usable) {
        if (!similarVendor(needle, '${row[2]}')) continue;
        matched++;
        final category = '${row[0]}'.trim();
        counts[category] = (counts[category] ?? 0) + 1;

        // 시트가 append-only 라 뒤에 있는 것이 최근이다. 다시 넣어 최신
        // 등장 위치로 끌어올린다(LinkedHashMap 의 삽입 순서).
        final desc = '${row[1]}'.trim();
        if (desc.isNotEmpty) {
          descriptions.remove(desc);
          descriptions[desc] = null;
        }
      }
      if (counts.isNotEmpty) {
        return CategoryGuess(
          tallies: _rankCategories(counts, limit: maxCandidates),
          reason: '업체명이 비슷한 과거 $matched건에서 쓴 비목입니다.',
          recentDescriptions: descriptions.keys.toList().reversed
              .take(_maxDescriptions)
              .toList(),
        );
      }
    }

    // ── 2. 내역에 같은 말이 들어간 행 ──────────────────────────────
    //
    // 겹치는 말이 여러 개면 **가장 많이 걸린 말 하나**만 쓴다. 두 말을
    // 합치면 근거 문구가 "'도서'·'8월' 이 들어간 12건" 이 되는데, 그중
    // 열 건은 `8월` 때문에 걸린 식대다.
    var bestWord = '';
    var bestRows = <List<Object?>>[];
    for (final word in _keywords(description ?? '')) {
      final hit = usable
          .where((row) => _squash('${row[1]}').contains(word))
          .toList();
      if (hit.length > bestRows.length) {
        bestWord = word;
        bestRows = hit;
      }
    }
    if (bestRows.isEmpty) return null;

    final counts = <String, int>{};
    for (final row in bestRows) {
      final category = '${row[0]}'.trim();
      counts[category] = (counts[category] ?? 0) + 1;
    }
    return CategoryGuess(
      tallies: _rankCategories(counts, limit: maxCandidates),
      reason:
          "내역에 '$bestWord'${_subjectParticle(bestWord)} "
          '들어간 과거 ${bestRows.length}건에서 쓴 비목입니다.',
    );
  }

  /// 내역에서 뽑은 **찾을 만한 말**들.
  ///
  /// 두 가지를 버린다:
  ///
  ///   - **한 글자** — `외`·`건` 하나로 과거 행 절반이 걸린다
  ///   - **숫자가 섞인 말** — `8월`·`2박` 은 비목과 아무 상관이 없는데
  ///     `8월 도서`·`8월 식대`·`8월 택시` 를 전부 끌어온다. 비목을 가르는
  ///     말은 숫자가 아닌 쪽(`도서`)이다
  static List<String> _keywords(String description) {
    final words = _squash(description).isEmpty
        ? <String>[]
        : description.split(RegExp(r'[\s,./·\-()\[\]]+'));
    return <String>[
      for (final w in words)
        if (_squash(w).length >= 2 && !w.contains(RegExp(r'\d'))) _squash(w),
    ];
  }
}

/// 과거 행을 **한 번 읽어** 만든 두 가지 — 업체명이 맞은 이력과, 못 맞췄을
/// 때의 추측.
///
/// 하나로 묶은 이유는 **같은 범위를 두 번 읽지 않기 위해서**다. 추측이
/// 필요한 순간은 추천이 비는 순간이라, 따로 부르면 시트를 두 번 읽고
/// 사용자는 그 시간을 두 번 기다린다.
@immutable
class VendorLookup {
  const VendorLookup({this.suggestion, this.guess});

  /// 과거 행에서 둘을 만든다. **순수 함수다** — 네트워크 없이 테스트한다.
  ///
  /// 업체명이 맞은 이력이 있으면 추측은 만들지 않는다 — 기록이 있는데 짐작을
  /// 같이 띄우면 어느 쪽이 근거 있는 값인지 흐려진다.
  factory VendorLookup.fromRows(
    List<List<Object?>> rows, {
    String? vendor,
    String? description,
  }) {
    final suggestion = (vendor ?? '').isEmpty
        ? null
        : VendorSuggestion.fromRows(rows, vendor: vendor!);
    if (suggestion != null) return VendorLookup(suggestion: suggestion);
    return VendorLookup(
      guess: CategoryGuess.fromRows(
        rows,
        vendor: vendor,
        description: description,
      ),
    );
  }

  /// 업체명이 **정확히** 맞은 과거 이력. 있으면 비목 칸을 채운다.
  final VendorSuggestion? suggestion;

  /// 그게 없을 때의 추측. **칸을 채우지 않는다** — 칩으로만 띄운다.
  final CategoryGuess? guess;
}

/// 매입내역 한 행에서 뽑은 것 — 카드번호 자리들과 그때 쓴 분류코드.
@immutable
class _CardClassRow {
  const _CardClassRow(this.slots, this.code);

  final List<String?> slots;
  final int code;
}

/// 매입내역 과거 행으로 만든 **카드 → 분류** 색인.
///
/// 분류의 1차 출처는 카드보유내역이다(`CardDirectory`). 이건 **그 시트에 그
/// 카드가 아직 없을 때의 두 번째 근거**다 — 운영팀이 카드를 늦게 적는 일이
/// 있고, 그 사이에 올라온 영수증은 분류를 통째로 못 정한다. 그런데 같은 카드로
/// 전에 제출한 건이 있으면 **어느 분류였는지는 매입내역에 이미 적혀 있다.**
///
/// 업체 이력 추천(`lookupForVendor`)과는 다르다. 그쪽은 "같은 업체면 같은
/// 비목" 이라는 경향이고, 이쪽은 **같은 카드**다 — 분류를 정하는 것은 어차피
/// 카드이므로 근거의 종류가 같고, 다만 출처가 마스터가 아니라 과거 기록이다.
/// 그래서 결과는 **추정**으로 표시한다(`applyCardClass`).
///
/// **옛 행에는 뒤 4자리밖에 없다.** 카드번호 칸이 전체 번호로 바뀌기 전에
/// 들어간 행이 그렇고, 앱이 적은 `766*` 같은 패턴도 섞여 있다. 그래서 비교는
/// 자리 호환 매칭이고, **뒤에서 맞춘다**(`CardDirectory.compatible`) —
/// 16자리로 조회해도 뒤 4자리만 적힌 과거 행이 같이 걸린다.
@immutable
class CardClassHistory {
  const CardClassHistory(this._rows);

  /// 시트 행들로 색인을 만든다. **순수 함수다** — 네트워크 없이 테스트한다.
  ///
  /// 행 모양은 `cardClassHistory` 가 읽는 범위와 같다: `H 분류코드 · I 분류명
  /// · J 카드번호`. **I열은 쓰지 않는다** — 분류명의 출처는 `_분류마스터`
  /// 하나다(두 시트가 어긋난 적이 있다. `card_repository.dart` 주석 참조).
  factory CardClassHistory.fromRows(List<List<Object?>> rows) {
    final out = <_CardClassRow>[];
    for (final row in rows) {
      if (row.length < 3) continue;
      final code = int.tryParse('${row[0] ?? ''}'.trim());
      if (code == null) continue;

      final slots = CardDirectory.slotsOf('${row[2] ?? ''}');
      // 숫자가 하나도 없는 행(`****`·`카드없음`·빈칸)은 버린다 —
      // 호환 매칭에서 **모든 조회에 걸려서** 아무 분류나 끌어온다.
      if (slots == null || !CardDirectory.hasAnyDigit(slots)) continue;

      out.add(_CardClassRow(slots, code));
    }
    return CardClassHistory(out);
  }

  final List<_CardClassRow> _rows;

  static const empty = CardClassHistory(<_CardClassRow>[]);

  /// 그 자리들과 어긋나지 않는 과거 행을 세어 **분류코드 → 건수**로 돌려준다.
  ///
  /// 건수가 많은 것부터, 같으면 코드 오름차순이다 — 화면 문구가 호출마다
  /// 뒤바뀌면 사용자가 다른 결과로 읽는다.
  Map<int, int> countsFor(List<String?> slots) {
    final counts = <int, int>{};
    for (final r in _rows) {
      if (!CardDirectory.compatible(r.slots, slots)) continue;
      counts[r.code] = (counts[r.code] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()
      ..sort(
        (a, b) => a.value != b.value
            ? b.value.compareTo(a.value)
            : a.key.compareTo(b.key),
      );
    return Map<int, int>.fromEntries(sorted);
  }

  /// 색인에 들어온 과거 행 수. 진단용이다.
  int get rowCount => _rows.length;
}

class SheetsRepository {
  const SheetsRepository({
    required this.spreadsheetId,
    this.dataSheetName = '매입내역',
  });

  final String spreadsheetId;

  /// 매입내역 탭. 추천 조회에만 쓴다 — append 는 `SheetRow.sheetName` 이 정한다.
  final String dataSheetName;

  /// 증빙링크 컬럼. `toSheetRow()` 의 **18번째**다.
  ///
  /// 컬럼을 늘리면 여기도 같이 움직여야 한다 —
  /// `test/sheet_evidence_link_test.dart` 가 18개라는 것을 박아둔다.
  static const evidenceColumn = 'R';

  /// 한 행을 그 항목이 속한 탭 맨 아래에 붙이고, **들어간 자리**를 돌려준다
  /// (`'매입내역'!A123:R123`). 자리를 못 받으면 null.
  ///
  /// `SheetRow` 를 받으므로 2차 사업비·3차 월결산이 와도 이 함수 하나면 된다.
  ///
  /// `values.append` 는 서버가 마지막 행을 찾아 붙이므로,
  /// 읽고→계산하고→쓰는 방식과 달리 동시 제출에서 서로 덮어쓰지 않는다.
  ///
  /// 자리를 돌려주는 이유는 하나뿐이다 — Drive 가 나중에 성공했을 때
  /// 증빙링크를 채우러 그 행으로 돌아가야 한다([fillEvidenceLink]).
  Future<String?> appendRow({
    required gapis.AuthClient client,
    required SheetRow row,
  }) async {
    final api = sheets.SheetsApi(client);
    final res = await api.spreadsheets.values.append(
      sheets.ValueRange(values: <List<Object>>[row.toSheetRow()]),
      spreadsheetId,
      row.sheetName,
      // USER_ENTERED = 시트가 날짜·숫자로 해석하게 둔다.
      // RAW 로 하면 전부 문자열이 돼서 회계 담당자의 수식·필터가 깨진다.
      valueInputOption: 'USER_ENTERED',
      insertDataOption: 'INSERT_ROWS',
      $fields: 'updates/updatedRange',
    );
    return res.updates?.updatedRange;
  }

  /// 이미 들어간 행의 **증빙링크 칸만** 나중에 채운다.
  ///
  /// ## 이게 append-only 의 유일한 예외다
  ///
  /// Drive 가 실패하고 시트 행이 먼저 들어가면 증빙링크가 빈 칸으로 나간다.
  /// 지금까지는 그걸 감수했다(ADR Decision 4) — 앱은 행을 고치지 않으므로
  /// 사용자가 Drive 링크를 손으로 붙여야 했다. 실제로 운영에서 한 건 생겼고,
  /// 재시도로 Drive 는 성공했는데 그 칸은 영원히 비어 있었다.
  ///
  /// 그래서 **그 칸 하나만** 쓰는 길을 열었다. 다른 칸은 건드리지 않는다:
  /// 금액·비목·분류는 회계가 보는 값이고, 수식 컬럼(해당년도·해당월·분류명)은
  /// ARRAYFORMULA 가 채운다.
  ///
  /// ## 행을 어떻게 다시 찾는가 — 그리고 왜 확인하는가
  ///
  /// 키 컬럼이 없다(ADR Decision 14). 대신 `values.append` 가 돌려준
  /// **들어간 자리**를 큐에 적어둔다. 그런데 그 자리는 영원하지 않다 —
  /// 회계 담당자가 위쪽 행을 지우거나 끼워 넣으면 번호가 밀린다.
  /// 밀린 줄 모르고 쓰면 **남의 행에 내 증빙링크를 적는다.**
  ///
  /// 그래서 쓰기 전에 그 행을 읽어 **업체명·내역이 그대로인지, 증빙링크 칸이
  /// 아직 비어 있는지** 확인한다. 어긋나면 아무것도 쓰지 않고 false 를
  /// 돌려준다 — 그때는 예전처럼 사람이 붙이면 된다. 최악의 경우가 "지금까지의
  /// 동작" 이 되도록 맞춘 것이다.
  ///
  /// (행을 확실히 따라가려면 `developerMetadata` 로 행에 표를 달고 그걸로
  /// 찾는 방법이 있다. 행이 밀려도 따라붙는다. 지금 필요한 것보다 큰 장치라
  /// 안 썼다 — 확인이 실패하는 일이 잦으면 그때 가면 된다.)
  ///
  /// 돌려주는 값: 채웠으면 true, **우리 행이 아니라고 판단해 쓰지 않았으면**
  /// false. 네트워크·권한 실패는 던진다 — 조용히 넘기지 않는다.
  Future<bool> fillEvidenceLink({
    required gapis.AuthClient client,
    required String appendedRange,
    required String url,
    required String expectVendor,
    required String expectDescription,
  }) async {
    final at = parseAppendedRow(appendedRange);
    if (at == null) return false;

    final api = sheets.SheetsApi(client);
    final res = await api.spreadsheets.values.get(
      spreadsheetId,
      '${at.sheet}!A${at.row}:$evidenceColumn${at.row}',
    );
    final values = res.values ?? <List<Object?>>[];
    final row = values.isEmpty ? <Object?>[] : values.first;

    // **이미 이 링크가 들어 있으면 끝난 것이다.** 쓰고 나서 응답을 받다가
    // 끊긴 뒤 다시 들어오면 이 길로 온다 — 그걸 "못 채웠다" 로 보고하면
    // 사용자가 다 된 일을 손으로 또 한다.
    if (evidenceCellOf(row) == url.trim()) return true;

    if (!isSameRow(row, vendor: expectVendor, description: expectDescription)) {
      return false;
    }

    await api.spreadsheets.values.update(
      sheets.ValueRange(values: <List<Object>>[<Object>[url]]),
      spreadsheetId,
      '${at.sheet}!$evidenceColumn${at.row}',
      // 링크는 USER_ENTERED 로 넣는다 — append 때와 같아야 한다.
      // RAW 로 넣으면 같은 칸이 건마다 다른 타입이 된다.
      valueInputOption: 'USER_ENTERED',
    );
    return true;
  }

  /// `values.append` 가 돌려준 범위에서 **탭 이름과 행 번호**를 꺼낸다.
  ///
  /// 받는 모양: `'매입내역'!A123:R123` — 탭 이름에 한글이 있으면 따옴표가
  /// 붙어 온다. 따옴표는 **그대로 들고 다닌다**(다시 범위를 만들 때 필요하다).
  ///
  /// 한 행을 붙였으므로 시작과 끝 행이 같아야 한다. 다르면 우리가 아는 모양이
  /// 아니므로 null — 모르는 범위에 쓰지 않는다.
  ///
  /// 네트워크를 타지 않게 따로 뺐다. 여기가 틀리면 **남의 행에 쓴다.**
  @visibleForTesting
  static ({String sheet, int row})? parseAppendedRow(String range) {
    final m = RegExp(r'^(.+)!([A-Z]+)(\d+):([A-Z]+)(\d+)$').firstMatch(range);
    if (m == null) return null;
    final from = int.tryParse(m.group(3)!);
    final to = int.tryParse(m.group(5)!);
    if (from == null || from != to) return null;
    return (sheet: m.group(1)!, row: from);
  }

  /// 그 행이 **여전히 우리 행**인가.
  ///
  /// 업체명(G)·내역(F)이 그대로이고 증빙링크(R)가 아직 비어 있어야 한다.
  /// 금액·날짜로도 볼 수 있지만 USER_ENTERED 로 들어간 숫자·날짜는 읽을 때
  /// 서식을 타서(`19,000`·`2026. 8. 5`) 글자 비교가 미끄러진다.
  /// 업체명·내역은 그냥 글자다.
  ///
  /// 업체명이 비어 있으면 **비교할 것이 없다는 뜻이므로 거부한다** —
  /// 그 조건으로는 빈 행 아무 곳에나 맞는다.
  /// 그 행의 증빙링크 칸(R) 값. 짧은 행이면 빈 글자.
  ///
  /// 시트는 **끝의 빈 칸을 빼고** 돌려준다 — 링크가 비어 있으면 행 길이가
  /// 18 보다 짧게 온다. 그래서 길이를 먼저 본다.
  @visibleForTesting
  static String evidenceCellOf(List<Object?> row) =>
      row.length > 17 ? '${row[17] ?? ''}'.trim() : '';

  @visibleForTesting
  static bool isSameRow(
    List<Object?> row, {
    required String vendor,
    required String description,
  }) {
    String cell(int i) => i < row.length ? '${row[i] ?? ''}'.trim() : '';

    if (vendor.trim().isEmpty) return false;
    // 이미 누군가 채웠으면(사람이 붙였거나 다른 재시도가 썼다) 덮지 않는다.
    if (evidenceCellOf(row).isNotEmpty) return false;
    if (cell(6) != vendor.trim()) return false;
    if (cell(5) != description.trim()) return false;
    return true;
  }

  /// 매입내역 과거 행에서 **카드 → 분류** 색인을 만든다.
  ///
  /// 카드보유내역에 없는 카드의 분류를 추정하는 데 쓴다([CardClassHistory]).
  /// 업체 이력과 **같은 구간**(최근 [maxRows] 행)을 본다 — 시트 전체를 매번
  /// 읽을 이유가 없고, 카드가 바뀌면 최근 행이 먼저 말해준다.
  Future<CardClassHistory> cardClassHistory({
    required gapis.AuthClient client,
    int maxRows = 2000,
  }) async {
    final api = sheets.SheetsApi(client);
    // H:J = 분류코드 · 분류명 · 카드번호. 가운데 I열은 **읽고도 버린다** —
    // 가운데를 건너뛰는 범위 표기가 없어서 같이 들어올 뿐이다.
    final res = await api.spreadsheets.values.get(
      spreadsheetId,
      "'$dataSheetName'!H2:J${maxRows + 1}",
    );
    return CardClassHistory.fromRows(res.values ?? <List<Object?>>[]);
  }

  /// 과거 처리를 찾아 **비목**을 제안하고, 못 찾으면 추측한다.
  ///
  /// **자동완성의 실제 승부처가 여기다.** OCR 은 비목을 못 뽑는다 —
  /// 영수증에 안 적혀 있다. 이 조회가 잘 되면 사용자가 34개 중에서 고를 일이 없다.
  ///
  /// 업체명이 정확히 맞으면 [VendorLookup.suggestion] 이고, 그게 없을 때
  /// 업체명·내역이 비슷한 행으로 만든 짐작이 [VendorLookup.guess] 다.
  /// **한 번 읽어 둘을 만든다** — 추측이 필요한 순간은 추천이 비는
  /// 순간이라, 따로 읽으면 사용자가 같은 조회를 두 번 기다린다.
  ///
  /// [vendor] 가 비어도 부른다 — OCR 이 상호를 못 읽은 건이 그렇고,
  /// 그때도 내역으로 추측할 수 있다.
  ///
  /// 분류는 제안하지 않는다 — 카드가 정한다([VendorSuggestion] 주석 참조).
  ///
  /// 시트 전체를 매번 읽지 않도록 [maxRows] 로 최근 구간만 본다.
  Future<VendorLookup> lookupForVendor({
    required gapis.AuthClient client,
    String? vendor,
    String? description,
    int maxRows = 2000,
  }) async {
    final api = sheets.SheetsApi(client);
    // E:I = 비목 · 내역 · 업체명 · 분류코드 · 분류명
    final res = await api.spreadsheets.values.get(
      spreadsheetId,
      "'$dataSheetName'!E2:I${maxRows + 1}",
    );
    // 세는 일은 `VendorLookup.fromRows` 가 한다 — 여기 두면 네트워크 없이는
    // 못 돌려서, 1등을 고르는 규칙이 조용히 틀려도 아무도 모른다.
    return VendorLookup.fromRows(
      res.values ?? <List<Object?>>[],
      vendor: vendor,
      description: description,
    );
  }
}

/// 비목·분류 마스터. **하드코딩하지 않는다** — 사업이 하나 생길 때마다
/// 앱을 재배포하게 된다. 시트의 별도 탭에서 읽어 캐시한다.
/// Sheets API 의 400 은 원인이 여럿인데 메시지가 불친절하다.
/// 가장 흔한 두 가지를 짚어준다.
Never _explainSheetsError(Object e, String spreadsheetId, String range) {
  if (e is sheets.DetailedApiRequestError && e.status == 400) {
    // 스프레드시트 ID 는 보통 44자다. 그보다 짧으면 **변환되지 않은 업로드 파일**일
    // 가능성이 크다 — Drive 는 이제 xlsx 를 자동 변환하지 않는다.
    // 그런 파일은 Sheets 에서 열려서 겉보기엔 멀쩡한데 Sheets API 는 못 읽는다.
    if (spreadsheetId.length < 40) {
      throw StateError(
        '시트를 읽지 못했습니다 (400).\n\n'
        'SPREADSHEET_ID 가 ${spreadsheetId.length}자입니다. '
        'Google 스프레드시트 ID 는 보통 44자입니다.\n'
        '엑셀 파일은 Drive 에 올려도 자동 변환되지 않습니다 — '
        '겉보기엔 열리지만 Sheets API 는 읽지 못합니다.\n\n'
        '그 파일을 열고 [파일] → [Google Sheets로 저장] 을 누른 뒤, '
        '새로 생긴 파일의 ID 를 .env 에 넣어주세요.\n\n'
        '원문: ${e.message}',
      );
    }
    throw StateError(
      '시트를 읽지 못했습니다 (400).\n'
      '범위: $range\n'
      '탭 이름이 정확한지 확인해 주세요.\n\n'
      '원문: ${e.message}',
    );
  }
  // 400 이 아니면 원래 예외를 그대로 올린다 — 여기서 감싸면 원인이 가려진다.
  // ignore: only_throw_errors — 받은 예외를 그대로 다시 던지는 것이라 안전하다.
  throw e;
}

class MasterDataRepository {
  const MasterDataRepository({
    required this.spreadsheetId,
    this.categorySheet = '_비목마스터',
    this.classSheet = '_분류마스터',
  });

  final String spreadsheetId;
  final String categorySheet;
  final String classSheet;

  /// 비목 34개(늘어날 수 있다).
  Future<List<String>> categories(gapis.AuthClient client) async {
    final api = sheets.SheetsApi(client);
    // 시트 이름은 작은따옴표로 감싼다. 밑줄로 시작하거나 한글·공백이 섞이면
    // 따옴표 없이는 A1 표기가 깨진다.
    final range = "'$categorySheet'!A2:A";
    final sheets.ValueRange res;
    try {
      res = await api.spreadsheets.values.get(spreadsheetId, range);
    } on Object catch (e) {
      _explainSheetsError(e, spreadsheetId, range);
    }
    return (res.values ?? <List<Object?>>[])
        .where((r) => r.isNotEmpty)
        .map((r) => '${r[0]}'.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// 분류코드 → 분류명.
  ///
  /// 시트에 수식을 두지 않으므로(위키 참조) **앱이 이걸로 분류명을 채운다.**
  Future<Map<int, String>> classNames(gapis.AuthClient client) async {
    final api = sheets.SheetsApi(client);
    final res = await api.spreadsheets.values.get(
      spreadsheetId,
      "'$classSheet'!A2:B",
    );
    final out = <int, String>{};
    for (final r in res.values ?? <List<Object?>>[]) {
      if (r.length < 2) continue;
      final code = int.tryParse('${r[0]}'.trim());
      if (code != null) out[code] = '${r[1]}'.trim();
    }
    return out;
  }
}
