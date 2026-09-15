/// 앱 로거.
///
/// "조용히 실패하면 안 된다" 는 이 앱의 원칙인데, 그렇다고 **사용자에게 보여줄
/// 실패**와 **로그에만 남길 실패**가 같은 건 아니다.
///
/// 예: 앱 시작 시 조용한 로그인 복구는 실패가 정상 경로다(처음 켠 사용자,
/// 로그아웃한 사용자). 그걸 화면에 띄우면 아무도 시도하지 않은 실패를 보게 된다.
/// 그런 건 여기로 보낸다.
library;

import 'package:logger/logger.dart';

final log = Logger(
  printer: PrettyPrinter(
    methodCount: 0,
    errorMethodCount: 5,
    printEmojis: false,
    dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
  ),
);
