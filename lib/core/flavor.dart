/// 이 빌드가 어느 환경인가.
///
/// ## 왜 dart-define 인가
///
/// 설정값은 `envied` 가 **빌드 시점에** `.env` 를 읽어 상수로 굽는다. 즉
/// 런타임 스위치로는 바꿀 수 없고, 환경마다 **다른 바이너리**가 나온다.
/// 그래서 선택도 빌드 시점에 해야 한다 — `--dart-define=FLAVOR=dev`.
///
/// 런타임 변수(전역 세터)로 두지 않은 이유: 누가 세터를 부르기 전에 설정을
/// 읽는 코드가 하나라도 있으면 그때는 조용히 틀린 값이 나간다. 컴파일 상수는
/// 그 순서 문제가 아예 없다.
///
/// ## 기본값을 두지 않는다
///
/// `FLAVOR` 가 없으면 **던진다.** 빠뜨렸을 때 운영으로 붙는 쪽이 훨씬 나쁘다 —
/// 개발용으로 테스트한다고 생각하면서 운영 시트에 행을 append 하고,
/// append-only 라 되돌릴 수도 없다.
///
/// 플래그를 손으로 적지 않도록 `Makefile` 에 묶어두었다(`make run-dev`).
library;

enum AppFlavor {
  dev('개발'),
  prod('운영');

  AppFlavor(this.label);

  /// 화면에 보여줄 이름.
  final String label;
}

/// `--dart-define=FLAVOR=...` 로 들어온 원문. 비면 빈 문자열이다.
const _raw = String.fromEnvironment('FLAVOR');

/// 지금 빌드의 환경. 지정되지 않았으면 **던진다**(기본값 없음).
///
/// `main()` 이 `runApp` 전에 한 번 읽으므로, 빠뜨린 빌드는 화면이 뜨기 전에
/// 죽는다 — 운영 시트에 닿을 기회가 없다.
AppFlavor get flavor => switch (_raw) {
  'dev' => AppFlavor.dev,
  'prod' => AppFlavor.prod,
  '' => throw StateError(
    'FLAVOR 가 지정되지 않았습니다.\n'
    '--dart-define=FLAVOR=dev 또는 prod 가 필요합니다.\n'
    '`make run-dev` / `make run-prod` 를 쓰면 플래그를 안 적어도 됩니다.',
  ),
  _ => throw StateError(
    'FLAVOR 값이 "$_raw" 입니다. dev 또는 prod 만 됩니다.',
  ),
};

/// 개발 환경인가. 화면에 표시를 띄울 때 쓴다.
bool get isDevFlavor => flavor == AppFlavor.dev;
