/// 월 폴더 기록을 읽는 규칙을 고정한다.
///
/// 이 탭은 **사람이 들어와 고칠 수 있는 자리**다(시트니까). 그리고 동시
/// 제출이 겹치면 앱이 스스로 같은 연월을 두 줄 적는다 — 그래서 "깨끗한
/// 입력" 을 가정할 수 없다. 겹쳤을 때 누구를 고를지가 이 기능의 핵심이라
/// 테스트로 박아둔다.
library;

import 'package:bodit_app/core/utils/filename.dart';
import 'package:bodit_app/data/remote/drive_folder_index.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('_드라이브폴더 탭 읽기', () {
    test('연월 → 폴더 ID 로 접는다', () {
      final map = DriveFolderIndex.parseIndex(<List<Object?>>[
        <Object?>['2608', 'folder-a', '2026-08-05T10:00:00'],
        <Object?>['2609', 'folder-b', '2026-09-01T09:00:00'],
      ]);
      expect(map, <String, String>{'2608': 'folder-a', '2609': 'folder-b'});
    });

    test('같은 연월이 두 줄이면 첫 줄을 쓴다 — 셋째 사람부터 한 폴더로 모인다', () {
      // 두 사람이 거의 동시에 그 달 첫 제출을 하면 각자 폴더를 만들고 각자
      // 적는다. 뒤에 오는 사람이 **먼저 적힌 쪽**으로 수렴해야 더 늘어나지
      // 않는다. 폴더가 월 단위라 한 번 갈리면 그 달 내내 갈린다.
      final map = DriveFolderIndex.parseIndex(<List<Object?>>[
        <Object?>['2608', 'folder-first'],
        <Object?>['2608', 'folder-second'],
      ]);
      expect(map['2608'], 'folder-first');
    });

    test('비거나 모자란 행은 건너뛴다 — 사람이 시트를 건드릴 수 있다', () {
      final map = DriveFolderIndex.parseIndex(<List<Object?>>[
        <Object?>['2608'], // ID 가 없다
        <Object?>['', 'folder-x'], // 연월이 없다
        <Object?>['2609', '  '], // ID 가 공백뿐
        <Object?>[' 2610 ', ' folder-y '], // 공백은 떨어낸다
      ]);
      expect(map, <String, String>{'2610': 'folder-y'});
    });

    test('숫자로 들어온 연월도 글자로 읽는다', () {
      // RAW 로 넣지만 사람이 손으로 적으면 시트가 숫자로 만들 수 있다.
      final map = DriveFolderIndex.parseIndex(<List<Object?>>[
        <Object?>[2608, 'folder-a'],
      ]);
      expect(map['2608'], 'folder-a');
    });

    test('일자 폴더 시절의 행이 남아 있어도 월 조회를 방해하지 않는다', () {
      // 폴더를 월 단위로 바꾸기 전 행(`260805`)은 탭에 그대로 남는다.
      // 지우지 않는다 — 그 폴더에 올라간 증빙이 어디 있는지의 기록이다.
      final map = DriveFolderIndex.parseIndex(<List<Object?>>[
        <Object?>['260805', 'folder-old-day'],
        <Object?>['2608', 'folder-month'],
      ]);
      expect(map['2608'], 'folder-month');
      expect(map['260805'], 'folder-old-day');
    });
  });

  group('폴더 이름', () {
    test('연월까지만 쓴다 — 일자는 파일 이름이 들고 있다', () {
      expect(formatMonthForFolder(DateTime(2026, 8, 5)), '2608');
      // 같은 달의 다른 날은 같은 폴더로 간다. 그게 이 형식의 목적이다.
      expect(
        formatMonthForFolder(DateTime(2026, 8, 31)),
        formatMonthForFolder(DateTime(2026, 8, 2)),
      );
    });

    test('한 자리 달은 0 을 붙인다', () {
      expect(formatMonthForFolder(DateTime(2026, 1, 9)), '2601');
      expect(formatMonthForFolder(DateTime(2026, 12, 9)), '2612');
    });

    test('파일명 접두가 폴더 이름으로 시작한다', () {
      // 폴더 `2608` 안의 파일이 `260805_…` 이다. 앞 두 자리를 파일명과 같은
      // `YY` 로 맞춘 이유 — 어긋나면 폴더와 파일이 다른 달처럼 보인다.
      final d = DateTime(2026, 8, 5);
      expect(formatDateForFilename(d), startsWith(formatMonthForFolder(d)));
    });
  });
}
