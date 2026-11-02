/// 날짜 폴더 기록을 읽는 규칙을 고정한다.
///
/// 이 탭은 **사람이 들어와 고칠 수 있는 자리**다(시트니까). 그리고 동시
/// 제출이 겹치면 앱이 스스로 같은 날짜를 두 줄 적는다 — 그래서 "깨끗한
/// 입력" 을 가정할 수 없다. 겹쳤을 때 누구를 고를지가 이 기능의 핵심이라
/// 테스트로 박아둔다.
library;

import 'package:bodit_app/core/utils/filename.dart';
import 'package:bodit_app/data/remote/drive_folder_index.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('_드라이브폴더 탭 읽기', () {
    test('날짜 → 폴더 ID 로 접는다', () {
      final map = DriveFolderIndex.parseIndex(<List<Object?>>[
        <Object?>['260805', 'folder-a', '2026-08-05T10:00:00'],
        <Object?>['260806', 'folder-b', '2026-08-06T09:00:00'],
      ]);
      expect(map, <String, String>{
        '260805': 'folder-a',
        '260806': 'folder-b',
      });
    });

    test('같은 날짜가 두 줄이면 첫 줄을 쓴다 — 셋째 사람부터 한 폴더로 모인다', () {
      // 두 사람이 거의 동시에 처음 제출하면 각자 폴더를 만들고 각자 적는다.
      // 뒤에 오는 사람이 **먼저 적힌 쪽**으로 수렴해야 더 늘어나지 않는다.
      final map = DriveFolderIndex.parseIndex(<List<Object?>>[
        <Object?>['260805', 'folder-first'],
        <Object?>['260805', 'folder-second'],
      ]);
      expect(map['260805'], 'folder-first');
    });

    test('비거나 모자란 행은 건너뛴다 — 사람이 시트를 건드릴 수 있다', () {
      final map = DriveFolderIndex.parseIndex(<List<Object?>>[
        <Object?>['260805'], // ID 가 없다
        <Object?>['', 'folder-x'], // 날짜가 없다
        <Object?>['260806', '  '], // ID 가 공백뿐
        <Object?>[' 260807 ', ' folder-y '], // 공백은 떨어낸다
      ]);
      expect(map, <String, String>{'260807': 'folder-y'});
    });

    test('숫자로 들어온 날짜도 글자로 읽는다', () {
      // RAW 로 넣지만 사람이 손으로 적으면 시트가 숫자로 만들 수 있다.
      final map = DriveFolderIndex.parseIndex(<List<Object?>>[
        <Object?>[260805, 'folder-a'],
      ]);
      expect(map['260805'], 'folder-a');
    });
  });

  test('폴더 이름은 파일명 접두와 같은 형식이다', () {
    // 두 규칙이 갈리면 `260805` 폴더 안에 `260806_…` 이 들어간 것처럼 보인다.
    // 폴더 이름도 `formatDateForFilename` 하나에서만 온다.
    expect(formatDateForFilename(DateTime(2026, 8, 5)), '260805');
  });
}
