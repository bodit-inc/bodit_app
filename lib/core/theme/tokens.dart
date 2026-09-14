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

  /// 상태: 실패
  static const danger = Color(0xFFE5484D);
  static const dangerBg = Color(0xFFFDE7E8);
  static const dangerFg = Color(0xFFC0272D);

  /// 안내 배너 (부가세 확인 등)
  static const noticeBg = Color(0xFFFFF4D6);
  static const noticeBorder = Color(0xFFF3D48A);
  static const noticeFg = Color(0xFF6B4A00);

  /// 추천 칩 — "과거 이력으로 제안했다" 를 뜻한다
  static const suggestBg = Color(0xFFE7F0FF);
  static const suggestFg = Color(0xFF0064D2);

  /// 오프라인 배너
  static const offlineBg = Color(0xFF4A4A4F);
}

/// 화면 전체 좌우 여백.
const screenPadding = EdgeInsets.all(Gap.lg);
