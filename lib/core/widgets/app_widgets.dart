/// 공통 위젯 배럴.
///
/// 화면은 이 파일 하나만 import 한다. 종류별 파일이 늘어나도 화면 코드는
/// 안 바뀐다 — 실제로 한 파일에 11개가 뭉쳐 있다가 쪼갰는데 화면은 그대로였다.
///
/// | 파일 | 담당 |
/// |---|---|
/// | `layout.dart` | 섹션·카드 |
/// | `rows.dart` | 카드 안의 줄 |
/// | `chips.dart` | 상태·추천 칩 |
/// | `fields.dart` | 입력 |
/// | `buttons.dart` | 반복되는 버튼 조합 |
/// | `dialogs.dart` | 확인·입력 다이얼로그 |
/// | `feedback.dart` | 보조설명·안내·실패·OCR 이탈 |
/// | `picker_sheet.dart` | 긴 목록에서 하나 고르기 |
library;

export 'buttons.dart';
export 'chips.dart';
export 'dialogs.dart';
export 'feedback.dart';
export 'fields.dart';
export 'layout.dart';
export 'picker_sheet.dart';
export 'rows.dart';
