/// 일시적인 네트워크 장애만 다시 시도한다.
///
/// ## 왜 필요한가
///
/// 운영에서 증빙 업로드가 `ClientException: Connection reset by peer` 로
/// 실패했다. 전송 도중 소켓이 끊긴 것이고, 사용자가 다시 눌렀더니 바로
/// 올라갔다 — **한 번 더 보내면 되는 실패**였다는 뜻이다.
///
/// 이 앱의 재시도는 지금까지 사용자가 [전송 시도] 를 누르는 것뿐이었다.
/// 그 결정(ADR Decision 12a: 오프라인 재전송은 수동)은 **안 나간 건을 언제
/// 다시 보낼지**에 대한 것이고, 한 호출 안에서 끊긴 연결을 다시 잡는 것은
/// 다른 얘기다. 여기서 포기하면 Drive 만 실패한 건이 되고 시트 행은
/// 증빙링크가 빈 채로 들어간다 — 시트는 append-only 라 되돌리는 값이 비싸다.
///
/// `package:googleapis` 가 막아주지 않는다. 라이브러리의 재시도는 resumable
/// 업로드에만 있고, 그마저 **HTTP 500·502·503 상태코드에만** 걸린다
/// (`resumable_media_uploader.dart` 의 `tryUpload`). 소켓이 끊기면
/// `ClientException` 이 그대로 올라온다.
///
/// ## 상태코드로 실패한 것은 다시 보내지 않는다
///
/// 403(권한 없음)·404(부모 폴더 없음)·400(범위가 틀렸다)을 세 번 반복해도
/// 답은 같다. 사용자를 기다리게 하고 로그만 세 배가 된다.
/// 다시 보내서 달라질 수 있는 것은 **연결이 끊긴 경우**뿐이다.
///
/// ## 다시 보내면 두 번 들어갈 수 있다
///
/// 서버가 요청을 다 받고 처리까지 한 뒤에 **응답을 돌려주다가** 끊기는 경우가
/// 있다. 이때 다시 보내면 같은 것이 두 번 만들어진다. 그래서 호출부는 그 대가가
/// 무엇인지 알고 감싸야 한다:
///
/// - 증빙 파일: 같은 파일이 두 개 올라갈 수 있다. 사람이 보고 지울 수 있고,
///   증빙이 아예 없는 쪽이 훨씬 나쁘다 → 감싼다
/// - 월 폴더: 두 개 생기면 그 달 증빙이 내내 갈린다 → **감싸기 전에 조회해서
///   내가 만든 것을 먼저 찾는다**(`DriveFolderIndex`)
/// - 시트 append: 감싸지 않는다. 같은 매입내역 행이 두 줄 들어가면 회계가
///   금액을 두 번 집계하고, append-only 라 앱이 지울 수 없다
library;

import 'dart:async';
import 'dart:io';

import 'package:bodit_app/core/log.dart';
import 'package:http/http.dart' as http;

/// 다시 보내면 결과가 달라질 수 있는 실패인가.
///
/// `package:http` 는 `SocketException` 을 잡아 `ClientException` 으로 바꿔
/// 던진다 — 그래서 **둘 다** 본다. 어느 쪽으로 올라오는지는 호출 경로에 따라
/// 다르고, 우리가 받은 운영 로그는 `ClientException` 이었다.
bool isTransientNetworkError(Object e) =>
    e is SocketException ||
    e is http.ClientException ||
    e is HandshakeException ||
    e is TimeoutException;

/// [action] 을 일시적 네트워크 장애에 한해 최대 [attempts] 번 시도한다.
///
/// [action] 은 **호출마다 새로 실행된다.** 요청 몸통에 스트림을 쓴다면
/// (`File.openRead()` 처럼 한 번만 들을 수 있는 것) 스트림을 이 클로저
/// **안에서** 만들어야 한다 — 바깥에서 만들어 두면 두 번째 시도가 이미 비어버린
/// 스트림을 보낸다.
///
/// 기다리는 시간은 시도마다 늘린다(0.5초 → 1초). 사용자가 화면 앞에서
/// 기다리는 중이라 길게 끌지 않는다 — 몇 초 안에 안 되면 [전송 시도] 가 있다.
Future<T> retryTransient<T>(
  Future<T> Function() action, {
  required String what,
  int attempts = 3,
  Duration delay = const Duration(milliseconds: 500),
}) async {
  for (var attempt = 1; ; attempt++) {
    try {
      return await action();
    } on Object catch (e) {
      // 마지막 시도였거나 다시 보내도 같은 답이면 그대로 올린다 —
      // 사유를 삼키지 않는다. 화면이 그 원문을 보여준다.
      if (attempt >= attempts || !isTransientNetworkError(e)) rethrow;
      final wait = delay * attempt;
      log.w('$what: 연결이 끊겼다 ($attempt/$attempts) — ${wait.inMilliseconds}ms 뒤 다시 시도: $e');
      await Future<void>.delayed(wait);
    }
  }
}
