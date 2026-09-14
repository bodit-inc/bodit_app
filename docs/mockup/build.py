# -*- coding: utf-8 -*-
"""
bodit app 화면 시안 생성기.
402x874pt(iPhone 17 Pro) HTML 을 만들고 Chrome 헤드리스로 PNG 를 뽑는다.
디자인은 목적이 아니다 — "기능이 이렇게 동작한다" 를 관련자에게 보여주는 용도.
"""
import pathlib, subprocess, shutil, sys, re

HERE = pathlib.Path(__file__).parent
SRC  = HERE / 'src'
SRC.mkdir(parents=True, exist_ok=True)

W, H, SCALE = 402, 874, 2
CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'

CSS = """
*{margin:0;padding:0;box-sizing:border-box;-webkit-font-smoothing:antialiased}
html,body{width:402px;height:874px;overflow:hidden}
body{font:400 15px/1.45 -apple-system,'SF Pro Text','Apple SD Gothic Neo',sans-serif;
     color:#111;background:#F2F2F7;display:flex;flex-direction:column}
/* ── 상태바 ── */
.sb{height:54px;flex:0 0 54px;display:flex;align-items:flex-end;justify-content:space-between;
    padding:0 24px 6px;font-size:15px;font-weight:600;letter-spacing:.2px}
.sb .r{display:flex;gap:5px;align-items:center;font-size:13px}
/* ── 네비 ── */
.nav{flex:0 0 auto;background:#fff;border-bottom:1px solid #E3E3E8;
     padding:8px 16px 12px;display:flex;align-items:center;justify-content:space-between}
.nav h1{font-size:20px;font-weight:700;letter-spacing:-.3px}
.nav .act{font-size:16px;color:#007AFF;font-weight:600}
.nav .act.dim{color:#B8B8BE}
.nav .back{font-size:16px;color:#007AFF}
/* ── 본문 ── */
.body{flex:1;overflow:hidden;padding:16px}
.body.p0{padding:0}
.sec{font-size:12px;font-weight:700;color:#8A8A8E;letter-spacing:.4px;margin:18px 4px 7px}
.sec:first-child{margin-top:2px}
.card{background:#fff;border-radius:12px;overflow:hidden}
.row{padding:11px 14px;border-bottom:1px solid #EFEFF2;display:flex;
     justify-content:space-between;align-items:center;gap:10px}
.row:last-child{border-bottom:0}
.row .lb{font-size:13px;color:#8A8A8E;flex:0 0 78px}
.row .vl{font-size:15px;flex:1;text-align:right;font-weight:500}
.row .vl.ph{color:#C2C2C7;font-weight:400}
/* 확인 필요 표시 */
.warn{background:#FFFBEA;box-shadow:inset 3px 0 0 #F5A623}
.warn .vl{color:#7A5200}
.badge{font-size:10px;font-weight:700;background:#F5A623;color:#fff;
       border-radius:4px;padding:2px 5px;white-space:nowrap}
.banner{background:#FFF4D6;border:1px solid #F3D48A;border-radius:10px;
        padding:10px 12px;font-size:13px;color:#6B4A00;line-height:1.5}
.banner b{font-weight:700}
.note{font-size:12px;color:#8A8A8E;padding:7px 14px 11px;line-height:1.5}
/* 버튼 */
.btn{background:#007AFF;color:#fff;border-radius:12px;padding:15px;text-align:center;
     font-size:17px;font-weight:600}
.btn.sec2{background:#fff;color:#007AFF;border:1px solid #D3D3D8}
.btn.sm{padding:8px 13px;font-size:13px;border-radius:8px;display:inline-block}
.big{background:#fff;border-radius:14px;padding:22px 16px;text-align:center;
     border:1px solid #E3E3E8}
.big .ic{font-size:32px;display:block;margin-bottom:8px}
.big .t{font-size:16px;font-weight:600}
.big .s{font-size:12px;color:#8A8A8E;margin-top:3px}
/* 칩 */
.chip{display:inline-flex;align-items:center;gap:5px;background:#E7F0FF;color:#0064D2;
      border-radius:15px;padding:6px 12px;font-size:14px;font-weight:600}
.chips{display:flex;gap:7px;flex-wrap:wrap}
.chip.gh{background:#F2F2F7;color:#5A5A5F;font-weight:500}
.why{font-size:12px;color:#4A8F4A;margin-top:6px;padding-left:2px}
/* 상태 점 */
.st{display:flex;align-items:center;gap:9px;padding:11px 14px;border-bottom:1px solid #EFEFF2}
.st:last-child{border-bottom:0}
.dot{width:19px;height:19px;border-radius:50%;flex:0 0 19px;display:flex;
     align-items:center;justify-content:center;font-size:11px;color:#fff;font-weight:700}
.ok{background:#2FA84F}.run{background:#007AFF}.wait{background:#D3D3D8}.err{background:#E5484D}
.st .n{font-size:15px;flex:1}
.st .m{font-size:12px;color:#8A8A8E}
/* 탭바 */
.tab{flex:0 0 76px;background:#fff;border-top:1px solid #E3E3E8;display:flex;padding-top:9px}
.tab div{flex:1;text-align:center;font-size:10px;color:#9A9A9E}
.tab div.on{color:#007AFF;font-weight:600}
.tab .ti{font-size:21px;display:block;margin-bottom:2px}
/* 기타 */
.thumb{background:#fff;border:1px solid #E3E3E8;border-radius:12px;padding:11px;
       display:flex;gap:11px;align-items:center}
.thumb .im{width:52px;height:66px;border-radius:6px;background:
   repeating-linear-gradient(#FBFBFB,#FBFBFB 5px,#EDEDF0 5px,#EDEDF0 6px);
   border:1px solid #DEDEE3;flex:0 0 52px}
.thumb .tx{font-size:13px;color:#6A6A6E;line-height:1.5}
.mono{font:600 12px/1.5 'SF Mono',ui-monospace,monospace;word-break:break-all}
.pill{font-size:11px;font-weight:700;padding:3px 8px;border-radius:20px;white-space:nowrap}
.p-ok{background:#E4F5E9;color:#1E7A38}
.p-wt{background:#EFEFF2;color:#6A6A6E}
.p-er{background:#FDE7E8;color:#C0272D}
.ctr{height:100%;display:flex;flex-direction:column;align-items:center;justify-content:center;
     text-align:center;padding:0 30px}
.spin{width:38px;height:38px;border:3px solid #E3E3E8;border-top-color:#007AFF;
      border-radius:50%;margin-bottom:18px}
"""

SB = ('<div class="sb"><span>9:41</span>'
      '<span class="r">●●●● WiFi <span style="border:1.5px solid #111;border-radius:3px;'
      'padding:0 3px;font-size:9px">86</span></span></div>')

def tabbar(on):
    f = lambda k,i,t: f'<div class="{"on" if on==k else ""}"><span class="ti">{i}</span>{t}</div>'
    return f'<div class="tab">{f("home","⌂","홈")}{f("list","☰","내 제출")}</div>'

def nav(title, left='', right=''):
    l = f'<span class="back">‹ {left}</span>' if left else '<span></span>'
    r = f'<span class="act">{right}</span>' if right else '<span></span>'
    if left: return f'<div class="nav">{l}<h1 style="font-size:17px">{title}</h1>{r}</div>'
    return f'<div class="nav"><h1>{title}</h1>{r}</div>'

SCREENS = []
def screen(slug, caption, body, bg='#F2F2F7'):
    SCREENS.append((slug, caption, body, bg))

# ══════════════════════════════════════════════════════════════════════════
# 화면 정의
# ══════════════════════════════════════════════════════════════════════════

screen('01-login', 'Google 계정으로 로그인', f'''
<div class="body"><div class="ctr">
  <div style="font-size:46px;margin-bottom:16px">🧾</div>
  <div style="font-size:25px;font-weight:700;letter-spacing:-.5px">매입내역</div>
  <div style="height:58px"></div>
  <div class="btn sec2" style="width:100%;display:flex;align-items:center;
       justify-content:center;gap:9px"><b style="font-size:17px">G</b> Google 계정으로 로그인</div>
</div></div>''')

screen('02-home', '홈 — 촬영 / 파일 선택, 전송 대기 큐, Sheets·Drive 바로가기', f'''
{nav('매입내역')}
<div class="body">
  <div style="display:flex;gap:11px">
    <div class="big" style="flex:1"><span class="ic">📷</span>
      <div class="t">증빙 촬영</div><div class="s">영수증·전표</div></div>
    <div class="big" style="flex:1"><span class="ic">🖼</span>
      <div class="t">파일 선택</div><div class="s">PDF·JPG·PNG</div></div>
  </div>
  <div class="sec">전송 대기</div>
  <div class="card"><div class="row">
    <div><div style="font-weight:600">2건이 전송을 기다리고 있습니다</div>
    <div style="font-size:12px;color:#8A8A8E;margin-top:2px">네트워크가 연결되면 자동 전송</div></div>
    <span class="pill p-wt">보기</span></div></div>
  <div class="sec">바로가기</div>
  <div class="card">
    <div class="row"><span>📊 매입내역 스프레드시트</span><span style="color:#C2C2C7">›</span></div>
    <div class="row"><span>📁 증빙 드라이브 폴더</span><span style="color:#C2C2C7">›</span></div>
    <div class="row"><span># purchase 채널</span><span style="color:#C2C2C7">›</span></div>
  </div>
  <div class="note" style="padding-left:4px">조회는 앱에서 다시 만들지 않고 원본으로 연결합니다</div>
</div>
{tabbar('home')}''')

screen('03-capture', '촬영 — 프레임 가이드', f'''
<div class="body p0" style="background:#000;position:relative">
  <div style="position:absolute;inset:64px 30px 190px;border:2px solid #fff;border-radius:10px;
       opacity:.9"></div>
  <div style="position:absolute;inset:82px 46px 208px;border-radius:6px;background:
       repeating-linear-gradient(#fff,#fff 8px,#E8E8E8 8px,#E8E8E8 9px);opacity:.28"></div>
  <div style="position:absolute;top:26px;left:0;right:0;text-align:center;color:#fff;
       font-size:14px">영수증이 프레임 안에 들어오게 찍어주세요</div>
  <div style="position:absolute;bottom:56px;left:0;right:0;display:flex;
       align-items:center;justify-content:center;gap:46px">
    <span style="color:#fff;font-size:13px">앨범</span>
    <div style="width:66px;height:66px;border-radius:50%;background:#fff;
         box-shadow:0 0 0 4px rgba(255,255,255,.35)"></div>
    <span style="color:#fff;font-size:13px">여러 장</span>
  </div>
</div>''')

screen('04-analyzing', 'OCR — 이미지에서 항목을 추출하고 과거 이력을 조회', f'''
{nav('분석 중', left='취소')}
<div class="body"><div class="ctr">
  <div class="spin"></div>
  <div style="font-size:17px;font-weight:600">영수증을 읽는 중…</div>
  <div style="height:26px"></div>
  <div class="card" style="width:100%;text-align:left">
    <div class="st"><span class="dot ok">✓</span><span class="n">이미지에서 항목 추출</span></div>
    <div class="st"><span class="dot run">›</span><span class="n">과거 매입내역 조회</span>
      <span class="m">업체명 대조</span></div>
    <div class="st"><span class="dot wait"></span><span class="n">비목·분류코드 추천</span></div>
  </div>
  <div style="font-size:12px;color:#9A9A9E;margin-top:16px;line-height:1.6">
    비목과 분류코드는 영수증에 없습니다.<br>과거에 같은 업체를 어떻게 처리했는지 보고 제안합니다.</div>
</div></div>''')

screen('05-review-one', '검토 폼 ① — 한 건. 저장될 파일명을 여기서 보고 고친다', f'''
{nav('검토', left='취소', right='제출')}
<div class="body">
  <div class="thumb"><div class="im"></div>
    <div class="tx"><b>영수증 1장</b><br>탭하면 원본을 크게 볼 수 있습니다</div></div>
  <div class="sec">기본</div>
  <div class="card">
    <div class="row"><span class="lb">소속날짜</span><span class="vl">2026-08-05</span></div>
    <div class="row"><span class="lb">지출날짜</span><span class="vl">2026-08-05</span></div>
    <div class="row"><span class="lb">업체명</span><span class="vl">영풍문고</span></div>
    <div class="row"><span class="lb">내역</span><span class="vl">8월 도서</span></div>
  </div>
  <div class="sec">저장될 파일명</div>
  <div class="card"><div style="padding:12px 14px;display:flex;gap:10px;
       justify-content:space-between;align-items:center">
    <span class="mono" style="flex:1">260805_[영풍문고]_[8월 도서]_영수증_19,000</span>
    <span style="color:#007AFF;font-size:14px;font-weight:600;white-space:nowrap">수정</span>
  </div></div>
  <div class="note">위 항목을 고치면 파일명도 따라 바뀝니다. 직접 고칠 수도 있습니다.</div>
</div>''')

screen('06-review-many', '검토 폼 ① — 여러 건을 한 번에 찍었을 때', f'''
{nav('검토 · 3건', left='취소', right='전체 제출')}
<div class="body">
  <div class="sec">읽은 증빙 3건</div>
  <div class="card">
    <div class="row"><div><div style="font-weight:600">영풍문고 · 19,000</div>
      <div style="font-size:12px;color:#8A8A8E">도서인쇄비 · 8월 도서</div></div>
      <span class="pill p-ok">확인됨</span></div>
    <div class="row"><div><div style="font-weight:600">스타벅스 · 12,400</div>
      <div style="font-size:12px;color:#8A8A8E">회의비 · 팀 미팅</div></div>
      <span class="pill p-ok">확인됨</span></div>
    <div class="row"><div><div style="font-weight:600">GS칼텍스 · 80,000</div>
      <div style="font-size:12px;color:#8A8A8E">차량유지비 · 주유</div></div>
      <span class="pill p-wt">확인 전</span></div>
  </div>
  <div class="note">한 건씩 눌러서 확인합니다. 3건 모두 확인하면 한 번에 제출됩니다.</div>
  <div class="sec">저장될 파일명</div>
  <div class="card"><div style="padding:11px 14px">
    <div class="mono" style="color:#5A5A5F">260805_[영풍문고]_[8월 도서]_영수증_19,000<br>
      260805_[스타벅스]_[팀 미팅]_영수증_12,400<br>
      260805_[GS칼텍스]_[주유]_영수증_80,000</div></div></div>
  <div style="height:12px"></div>
  <div class="btn">3건 전체 제출</div>
</div>''')

screen('07-suggest', '검토 폼 ② — 비목·분류코드는 과거 이력으로 추천 + 근거 표시', f'''
{nav('검토', left='취소', right='제출')}
<div class="body">
  <div class="sec">분류 — 영수증에 없는 항목</div>
  <div class="card">
    <div class="row" style="flex-direction:column;align-items:stretch;gap:8px">
      <span class="lb" style="flex:none">비목</span>
      <div class="chips"><span class="chip">도서인쇄비 ✓</span>
        <span class="chip gh">사무용품비</span><span class="chip gh">직접 선택 ›</span></div>
      <div class="why">✓ 영풍문고는 지난 3건 모두 도서인쇄비였습니다</div>
    </div>
    <div class="row" style="flex-direction:column;align-items:stretch;gap:8px">
      <span class="lb" style="flex:none">분류코드 / 분류명</span>
      <div class="chips"><span class="chip">1 · 법인 ✓</span>
        <span class="chip gh">직접 선택 ›</span></div>
      <div class="why">✓ 분류명은 시트가 코드로 자동 계산합니다</div>
    </div>
  </div>
  <div class="sec">참고</div>
  <div class="card"><div class="note" style="padding:12px 14px">
    비목 34개를 매번 훑지 않도록, 같은 업체를 과거에 어떻게 처리했는지 보고 먼저 제안합니다.
    <b>처음 보는 업체만</b> 직접 고르면 됩니다. 쓸수록 손댈 일이 줄어듭니다.</div></div>
</div>''')

screen('08-picker', '비목 선택 — 추천·최근순으로 정렬된 검색 목록', f"""
{nav('검토', left='취소', right='제출')}
<div style="position:relative;flex:1;overflow:hidden">
  <div class="body" style="height:100%">
    <div class="sec">분류</div>
    <div class="card"><div class="row"><span class="lb">비목</span>
      <span class="vl ph">선택하세요</span></div></div>
  </div>
  <div style="position:absolute;inset:0;background:rgba(0,0,0,.28)"></div>
  <div style="position:absolute;left:0;bottom:0;width:402px;background:#fff;
       border-radius:16px 16px 0 0;padding:12px 16px 20px;height:588px">
    <div style="width:36px;height:5px;background:#D9D9DE;border-radius:3px;
         margin:0 auto 14px"></div>
    <div style="font-size:17px;font-weight:700;margin-bottom:11px">비목 선택</div>
    <div style="background:#F2F2F7;border-radius:10px;padding:9px 12px;color:#9A9A9E;
         font-size:15px">🔍 검색</div>
    <div class="sec">추천</div>
    <div class="card" style="background:#F1F9F3;border:1px solid #CDE8D5">
      <div class="row"><span style="font-weight:600">도서인쇄비</span>
        <span class="pill p-ok">지난 3건</span></div></div>
    <div class="sec">최근 사용</div>
    <div class="card">
      <div class="row"><span>사무용품비</span><span style="color:#C2C2C7">›</span></div>
      <div class="row"><span>회의비</span><span style="color:#C2C2C7">›</span></div>
      <div class="row"><span>여비교통비</span><span style="color:#C2C2C7">›</span></div>
    </div>
    <div class="sec">전체 34개</div>
    <div class="card">
      <div class="row"><span>광고선전비</span><span style="color:#C2C2C7">›</span></div>
      <div class="row"><span>금형제작비</span><span style="color:#C2C2C7">›</span></div>
      <div class="row"><span>복리후생비</span><span style="color:#C2C2C7">›</span></div>
    </div>
  </div>
</div>""")

screen('09-amount', '검토 폼 ③ — 금액. 부가세는 자동 계산하지 않고 물어본다', f'''
{nav('검토', left='취소', right='제출')}
<div class="body">
  <div class="sec">금액</div>
  <div class="card">
    <div class="row"><span class="lb">총금액</span><span class="vl">19,000</span></div>
    <div class="row"><span class="lb">공급가액</span><span class="vl">19,000</span></div>
    <div class="row"><span class="lb">부가세</span><span class="vl">0</span></div>
  </div>
  <div style="height:11px"></div>
  <div class="banner"><b>부가세가 0원으로 읽혔습니다.</b><br>
    도서는 면세라 0원이 맞습니다. 과세 영수증인데 총액만 찍혀 있다면 아래로 나눌 수 있습니다.
    <div style="margin-top:9px"><span class="btn sm sec2"
      style="border:1px solid #D9BE7A;color:#7A5200">1.1로 나누기</span></div></div>
  <div class="sec">결제수단</div>
  <div class="card">
    <div class="row"><span class="lb">카드번호</span><span class="vl">•••• 1234</span></div>
    <div class="row"><span class="lb">비고</span><span class="vl ph">선택 입력</span></div>
  </div>
  <div class="note">카드번호는 뒤 4자리만 저장합니다. 앞자리는 인식 즉시 버립니다.</div>
  <div style="height:10px"></div>
  <div class="btn">제출</div>
</div>''')

screen('10-submitting', '제출 — 세 곳에 동시에 올라간다', f'''
{nav('제출 중')}
<div class="body">
  <div class="sec">전송</div>
  <div class="card">
    <div class="st"><span class="dot ok">✓</span><span class="n">Google Sheets</span>
      <span class="m">행 추가됨</span></div>
    <div class="st"><span class="dot ok">✓</span><span class="n">Google Drive</span>
      <span class="m">2026-08 폴더</span></div>
    <div class="st"><span class="dot run">›</span><span class="n">Slack #purchase</span>
      <span class="m">사진 업로드 중</span></div>
  </div>
  <div class="sec">저장되는 파일명</div>
  <div class="card"><div style="padding:12px 14px">
    <div class="mono">260805_[영풍문고]_[8월 도서]_영수증_19,000</div></div></div>
  <div class="note">업체명·내역은 대괄호로 감싸 값에 <b>_</b> 가 들어가도 경계가 안 무너집니다.</div>
</div>''')

screen('11-done', '완료 — Slack 에 올라간 모습까지 확인', f'''
{nav('완료')}
<div class="body">
  <div style="text-align:center;padding:14px 0 20px">
    <div style="width:56px;height:56px;border-radius:50%;background:#2FA84F;color:#fff;
         font-size:29px;line-height:56px;margin:0 auto 11px">✓</div>
    <div style="font-size:19px;font-weight:700">등록했습니다</div>
    <div style="font-size:13px;color:#8A8A8E;margin-top:4px">영풍문고 · 19,000원 · 도서인쇄비</div>
  </div>
  <div class="sec">Slack #purchase 에 올라간 내용</div>
  <div class="card"><div style="padding:12px 14px;display:flex;gap:10px">
    <div style="width:34px;height:34px;border-radius:7px;background:#4A154B;color:#fff;
         font-size:11px;font-weight:700;display:flex;align-items:center;
         justify-content:center;flex:0 0 34px">매입</div>
    <div style="flex:1">
      <div style="font-size:13px"><b>영풍문고</b> · 19,000원</div>
      <div style="font-size:12px;color:#6A6A6E;margin-top:2px">
        도서인쇄비 · 8월 도서 · 카드 ••••1234<br>등록 james@bodit.co</div>
      <div style="margin-top:8px;width:82px;height:96px;border-radius:6px;background:
           repeating-linear-gradient(#FBFBFB,#FBFBFB 5px,#EDEDF0 5px,#EDEDF0 6px);
           border:1px solid #DEDEE3"></div>
    </div></div></div>
  <div style="height:14px"></div>
  <div style="display:flex;gap:10px">
    <div class="btn sec2" style="flex:1">목록 보기</div>
    <div class="btn" style="flex:1">계속 등록</div>
  </div>
</div>''')

screen('12-list', '내 제출 목록 — 부분 실패(Slack 만 실패)가 여기서 보인다', f'''
{nav('내 제출')}
<div class="body">
  <div class="sec">오늘</div>
  <div class="card">
    <div class="row"><div><div style="font-weight:600">영풍문고 · 19,000</div>
      <div style="font-size:12px;color:#8A8A8E">도서인쇄비 · 14:22</div></div>
      <span class="pill p-ok">완료</span></div>
    <div class="row" style="background:#FFF6F6;box-shadow:inset 3px 0 0 #E5484D">
      <div><div style="font-weight:600">스타벅스 · 12,400</div>
      <div style="font-size:12px;color:#C0272D">Sheets·Drive 완료 / Slack 실패 · 재시도 대기</div></div>
      <span class="pill p-er">재시도</span></div>
    <div class="row"><div><div style="font-weight:600">GS칼텍스 · 80,000</div>
      <div style="font-size:12px;color:#8A8A8E">전송 대기 · 오프라인</div></div>
      <span class="pill p-wt">대기</span></div>
  </div>
  <div class="sec">어제</div>
  <div class="card">
    <div class="row"><div><div style="font-weight:600">쿠팡 · 34,900</div>
      <div style="font-size:12px;color:#8A8A8E">사무용품비</div></div>
      <span class="pill p-ok">완료</span></div>
  </div>
  <div class="note">목적지가 3곳이라 하나만 실패할 수 있습니다.
    실패한 곳만 다시 보내므로 시트에 같은 행이 두 번 들어가지 않습니다.</div>
</div>
{tabbar('list')}''')

screen('13-offline', '오프라인·약한 연결 — 기기에 임시저장. 대기 목록은 시간순', f'''
{nav('매입내역')}
<div class="body">
  <div style="background:#4A4A4F;color:#fff;border-radius:10px;padding:11px 13px;
       font-size:13px;line-height:1.55;display:flex;gap:9px">
    <span>✈️</span><span>지금 등록한 건은 기기에 임시저장합니다.<br>
      인터넷 연결이 원활해지면 전송 시도해주세요.</span></div>
  <div style="height:13px"></div>
  <div style="display:flex;gap:11px">
    <div class="big" style="flex:1"><span class="ic">📷</span>
      <div class="t">증빙 촬영</div><div class="s">오프라인에서도 가능</div></div>
    <div class="big" style="flex:1"><span class="ic">🖼</span>
      <div class="t">파일 선택</div><div class="s">PDF·JPG·PNG</div></div>
  </div>
  <div class="sec">전송 대기 3건 · 최근순</div>
  <div class="card">
    <div class="row"><div><div style="font-weight:600">택시 · ¥3,400</div>
      <div style="font-size:12px;color:#8A8A8E">오늘 18:40</div></div>
      <span class="pill p-wt">대기</span></div>
    <div class="row"><div><div style="font-weight:600">하네다공항 · ¥1,200</div>
      <div style="font-size:12px;color:#8A8A8E">오늘 11:05</div></div>
      <span class="pill p-wt">대기</span></div>
    <div class="row"><div><div style="font-weight:600">GS칼텍스 · 80,000</div>
      <div style="font-size:12px;color:#8A8A8E">어제 09:12</div></div>
      <span class="pill p-wt">대기</span></div>
  </div>
  <div style="height:12px"></div>
  <div class="btn">전송 시도</div>
  <div class="note" style="text-align:center">오프라인에서는 항목 자동 추출이 안 됩니다.
    사진만 찍어두고 연결되면 그때 읽어서 채웁니다.</div>
</div>''')

# ══════════════════════════════════════════════════════════════════════════
# 렌더
# ══════════════════════════════════════════════════════════════════════════
def render():
    if not pathlib.Path(CHROME).exists():
        sys.exit(f"Chrome 없음: {CHROME}")
    for slug, cap, body, bg in SCREENS:
        html = (f'<!doctype html><meta charset="utf-8"><style>{CSS}</style>'
                f'<body style="background:{bg}">{SB}{body}</body>')
        (SRC / f'{slug}.html').write_text(html, encoding='utf-8')
    for slug, *_ in SCREENS:
        out = HERE / f'{slug}.png'
        subprocess.run([CHROME, '--headless=new', '--disable-gpu', '--hide-scrollbars',
                        f'--screenshot={out}',
                        f'--window-size={W},{H}', f'--force-device-scale-factor={SCALE}',
                        (SRC / f'{slug}.html').as_uri()],
                       check=True, capture_output=True, timeout=60)
        print(f"  {out.name}  {out.stat().st_size//1024}KB")
    (HERE / 'INDEX.md').write_text(
        "# bodit app 화면 시안\n\n"
        "`build.py` 로 생성한다. 디자인 확정본이 아니라 **동작 흐름 공유용**이다.\n\n"
        "| # | 파일 | 화면 |\n|---|---|---|\n" +
        "".join(f"| {i+1} | `{s}.png` | {c} |\n" for i,(s,c,*_) in enumerate(SCREENS)) +
        "\n재생성: `python3 docs/mockup/build.py`\n", encoding='utf-8')
    print(f"\n총 {len(SCREENS)}장")


# ══════════════════════════════════════════════════════════════════════════
# 흐름도 한 장 (공유용 컨택트 시트)
# ══════════════════════════════════════════════════════════════════════════
def contact_sheet():
    PW, COLS = 200, 5
    PH = round(PW * H / W)
    PAGEW = COLS*PW + (COLS-1)*18 + 60
    cells = ""
    for i, (slug, cap, *_) in enumerate(SCREENS):
        cells += f'''<div class="c">
          <div class="hd"><span class="no">{i+1}</span><span class="cp">{cap}</span></div>
          <img src="{(HERE/f'{slug}.png').as_uri()}">
        </div>'''
    sheet = f'''<!doctype html><meta charset="utf-8"><style>
    *{{margin:0;padding:0;box-sizing:border-box}}
    body{{font:400 13px/1.5 -apple-system,'Apple SD Gothic Neo',sans-serif;color:#111;
         background:#fff;padding:34px 30px 30px;width:{PAGEW}px}}
    h1{{font-size:25px;font-weight:800;letter-spacing:-.5px}}
    .sub{{font-size:13px;color:#767680;margin:7px 0 4px;line-height:1.6}}
    .meta{{font-size:11px;color:#9A9AA0;margin-bottom:24px}}
    .grid{{display:grid;grid-template-columns:repeat({COLS},{PW}px);gap:26px 18px}}
    .c{{width:{PW}px}}
    .hd{{display:flex;gap:6px;margin-bottom:7px;min-height:46px}}
    .no{{flex:0 0 19px;height:19px;border-radius:50%;background:#111;color:#fff;
        font-size:11px;font-weight:700;display:flex;align-items:center;justify-content:center}}
    .cp{{font-size:11px;line-height:1.45;color:#3A3A40}}
    img{{width:{PW}px;height:{PH}px;border:1px solid #DDD;border-radius:11px;display:block}}
    .ft{{margin-top:26px;padding-top:16px;border-top:1px solid #E5E5EA;
        font-size:11px;color:#8A8A90;line-height:1.8}}
    .ft b{{color:#3A3A40}}
    </style><body>
    <h1>bodit app — 매입내역 자동완성 화면 흐름</h1>
    <div class="sub">증빙을 올리면 항목을 자동으로 채우고, 확인 후 제출하면
      <b>Google Sheets · Google Drive · Slack</b> 세 곳에 동시에 올라간다.
      승인 단계는 없다 — 회계 담당자는 Sheets 를 읽기만 한다.</div>
    <div class="meta">동작 흐름 공유용 시안 · 디자인 확정본 아님 · iPhone 17 Pro (402×874pt) · 2026-09-14</div>
    <div class="grid">{cells}</div>
    <div class="ft">
      <b>이 시안이 보여주려는 것</b><br>
      · 15개 필드를 처음부터 채우지 않는다 — OCR 로 읽어서 미리 채워둔다(③④⑤)<br>
      · <b>한 번에 여러 장</b>을 찍어도 된다 — 건별로 확인하고 한 번에 제출한다(⑥)<br>
      · <b>저장될 파일명</b>을 검토 화면에서 보고 직접 고칠 수 있다(⑤⑥)<br>
      · 비목·분류코드는 영수증에 없다 — <b>과거에 같은 업체를 어떻게 처리했는지</b> 보고 제안한다(⑦⑧)<br>
      · 부가세는 자동 계산하지 않는다 — 면세가 있어서 물어본다(⑨)<br>
      · 목적지가 3곳이라 <b>하나만 실패</b>할 수 있다. 실패한 곳만 다시 보낸다(⑩⑫)<br>
      · 오프라인·약한 연결에서는 <b>기기에 임시저장</b>한다(⑬)
    </div></body>'''
    # 문서 실제 높이를 먼저 재고(1차 dump-dom) 그 크기로 캡처한다(2차).
    # Chrome 은 --window-size 만큼만 찍으므로 안 재면 아래가 잘리거나 여백이 남는다.
    probe = sheet.replace('</body>',
        '<div id="h"></div><script>document.getElementById("h").textContent='
        '"PAGEH="+Math.ceil(document.body.scrollHeight)</script></body>')
    (SRC/'_flow.html').write_text(probe, encoding='utf-8')
    dom = subprocess.run([CHROME,'--headless=new','--disable-gpu','--allow-file-access-from-files',
                          '--dump-dom', f'--window-size={PAGEW},1200', (SRC/'_flow.html').as_uri()],
                         capture_output=True, text=True, timeout=120).stdout
    m = re.search(r'PAGEH=(\d+)', dom)
    ph = int(m.group(1)) + 8 if m else 1400
    (SRC/'_flow.html').write_text(sheet, encoding='utf-8')
    out = HERE/'00-flow-overview.png'
    subprocess.run([CHROME,'--headless=new','--disable-gpu','--hide-scrollbars',
                    '--allow-file-access-from-files', f'--screenshot={out}',
                    f'--window-size={PAGEW},{ph}','--force-device-scale-factor=2',
                    (SRC/'_flow.html').as_uri()], check=True, capture_output=True, timeout=120)
    print(f"  {out.name}  {PAGEW}x{ph}pt  {out.stat().st_size//1024}KB")

if __name__ == '__main__':
    render()
    contact_sheet()
