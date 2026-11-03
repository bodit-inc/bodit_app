/// 디자인 토큰.
///
/// 화면 코드에 `Color(0xFF...)` 나 `EdgeInsets.all(16)` 을 직접 쓰지 않는다.
/// 13개 화면에 값이 흩어지면 나중에 못 바꾼다. 여기 모아두면 변경이 파일 하나다.
///
/// 시안(`docs/mockup/`)은 iOS 풍으로 그려져 있지만 **그건 흐름 명세지 픽셀 명세가
/// 아니다.** 실제 앱은 Material 3 기본값을 따르고 토큰만 맞춘다.
/// 브랜드 컬러·아이콘은 기능이 자리잡은 뒤에 정한다.
library;

import 'package:flutter/material.dart';

/// 간격. 4의 배수로 통일한다.
abstract final class Gap {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

/// 모서리 둥글기.
abstract final class Radii {
  static const card = 12.0;
  static const button = 12.0;
  static const pill = 20.0;
  static const sheet = 16.0;
}

/// 의미 기반 색. 팔레트가 아니라 **역할**로 이름 짓는다 —
/// 나중에 브랜드 컬러가 정해져도 이름은 그대로 두고 값만 바꾼다.
abstract final class AppColors {
  /// 상태: 성공/완료
  static const success = Color(0xFF2FA84F);
  static const successBg = Color(0xFFE4F5E9);
  static const successFg = Color(0xFF1E7A38);

  /// 상태: 대기/중립
  static const neutralBg = Color(0xFFEFEFF2);
  static const neutralFg = Color(0xFF6A6A6E);

  /// 상태: 실패 — 그리고 `NoticeBanner`(확인 필요).
  ///
  /// 배너는 "읽고 지나가도 되는 안내" 가 아니다. 띠가 뜨는 건은 대개 사용자가
  /// 손을 봐야 하는 건이고, 시트는 append-only 라 틀린 채 제출되면 앱으로
  /// 되돌릴 방법이 없다. 그래서 **배너만** 실패와 같은 강도로 올렸다.
  ///
  /// 칸에 붙는 인라인 경고는 노랑(아래 caution)으로 남긴다 — 전부 빨강이면
  /// 강도 차이가 다시 안 보이고, 그러면 진짜 실패가 묻힌다.
  static const danger = Color(0xFFE5484D);
  static const dangerBg = Color(0xFFFDE7E8);
  static const dangerBorder = Color(0xFFF9C9CB);
  static const dangerFg = Color(0xFFC0272D);

  /// 주의 — "확인은 필요하지만 실패는 아니다".
  ///
  /// 칸 옆·칸 아래에 **인라인으로** 붙는 것들이 쓴다: 중간 확신도 아이콘
  /// (`LabeledRow`) · 안 고른 추천 칩(`SuggestChip`) · 빈 항목 띠.
  ///
  /// **`NoticeBanner` 는 이 색이 아니다** — 위 danger 를 쓴다. 그래서 이름도
  /// `notice*` 가 아니다. 배너가 안 쓰는 색에 배너 이름을 붙여두면 다음에
  /// 읽는 사람이 반대로 읽는다.
  static const cautionBg = Color(0xFFFFF4D6);
  static const cautionBorder = Color(0xFFF3D48A);
  static const cautionFg = Color(0xFF6B4A00);

  /// 추천 칩 — "과거 이력으로 제안했다" 를 뜻한다
  static const suggestBg = Color(0xFFE7F0FF);
  static const suggestFg = Color(0xFF0064D2);

  /// 오프라인 배너
  static const offlineBg = Color(0xFF4A4A4F);
}

/// 화면 전체 좌우 여백.
const screenPadding = EdgeInsets.all(Gap.lg);
