"""개발(dev) 빌드용 앱 아이콘을 만든다.

## 왜 스크립트인가

운영 아이콘이 바뀌면 개발 아이콘도 같이 바뀌어야 한다. 이미지를 손으로
편집해 커밋해두면 그때 한쪽만 낡는다 — 어느 쪽이 원본인지도 모르게 된다.
운영 아이콘을 **입력으로** 삼아 매번 다시 만든다.

## 무엇을 하나

운영 아이콘 한가운데에 주황 띠와 흰 `dev` 글자를 얹는다. 런처에서 48px 로
줄어들어도 띠 색만으로 구분되도록 글자가 아니라 **색 덩어리**를 먼저 만든다.

    python3 tool/make_dev_icons.py

산출물(둘 다 개발 빌드에서만 쓰인다):
  - ios/Runner/Assets.xcassets/AppIcon-dev.appiconset/   (dev 설정의 ASSETCATALOG_COMPILER_APPICON_NAME)
  - android/app/src/dev/res/...                          (dev 소스셋이 main 을 덮어쓴다)
"""

from __future__ import annotations

import json
import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent

# 브랜드 색. 아이콘에서 뽑았다 — 주황 점과 같은 값이라 띠가 로고와 따로 놀지 않는다.
ORANGE = (235, 86, 45, 255)
WHITE = (255, 255, 255, 255)

# 띠가 아이콘 높이에서 차지하는 구간. 가운데 32%.
BAND_TOP, BAND_BOTTOM = 0.34, 0.66

# macOS 기본 폰트. 굵을수록 작은 크기에서 살아남는다.
FONT_CANDIDATES = [
    "/System/Library/Fonts/Supplemental/Arial Black.ttf",
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
]


def _font(px: int) -> ImageFont.FreeTypeFont:
    for path in FONT_CANDIDATES:
        if Path(path).exists():
            return ImageFont.truetype(path, px)
    raise SystemExit(f"쓸 폰트를 찾지 못했습니다: {FONT_CANDIDATES}")


def badge(src: Path, dst: Path, size: int | None = None) -> None:
    """`src` 아이콘에 dev 띠를 얹어 `dst` 로 저장한다."""
    im = Image.open(src).convert("RGBA")
    if size is not None and im.size != (size, size):
        im = im.resize((size, size), Image.LANCZOS)
    w, h = im.size

    top, bottom = int(h * BAND_TOP), int(h * BAND_BOTTOM)
    draw = ImageDraw.Draw(im)
    draw.rectangle([0, top, w, bottom], fill=ORANGE)

    # 글자는 띠 높이에 맞춰 키운다. 띠를 꽉 채우면 작은 크기에서 뭉개지므로 72%.
    band_h = bottom - top
    font = _font(max(8, int(band_h * 0.72)))
    # anchor="mm" = 중앙 정렬. 글자의 실제 잉크 기준이라 크기가 달라져도 안 흔들린다.
    draw.text((w / 2, (top + bottom) / 2), "dev", font=font, fill=WHITE, anchor="mm")

    dst.parent.mkdir(parents=True, exist_ok=True)
    im.save(dst)


def build_ios() -> None:
    src_set = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    dst_set = ROOT / "ios/Runner/Assets.xcassets/AppIcon-dev.appiconset"
    if dst_set.exists():
        shutil.rmtree(dst_set)
    dst_set.mkdir(parents=True)

    # Contents.json 은 그대로 복사한다 — 파일 이름을 같게 유지하므로 손댈 게 없다.
    contents = json.loads((src_set / "Contents.json").read_text())
    (dst_set / "Contents.json").write_text(json.dumps(contents))

    for png in sorted(src_set.glob("*.png")):
        badge(png, dst_set / png.name)
    print(f"iOS: {len(list(dst_set.glob('*.png')))}개 생성 → {dst_set.relative_to(ROOT)}")


def build_android() -> None:
    main_res = ROOT / "android/app/src/main/res"
    dev_res = ROOT / "android/app/src/dev/res"
    if dev_res.exists():
        shutil.rmtree(dev_res)

    made = 0
    for density in ("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi"):
        # 구형 런처가 쓰는 정사각 아이콘.
        legacy = main_res / f"mipmap-{density}/ic_launcher.png"
        if legacy.exists():
            badge(legacy, dev_res / f"mipmap-{density}/ic_launcher.png")
            made += 1
        # API 26+ 의 adaptive icon 은 이쪽을 본다. 여기를 안 덮으면 최신
        # 런처에서는 운영 아이콘이 그대로 뜬다 — 위 legacy 만으로는 모자라다.
        fg = main_res / f"drawable-{density}/ic_launcher_foreground.png"
        if fg.exists():
            badge(fg, dev_res / f"drawable-{density}/ic_launcher_foreground.png")
            made += 1
    print(f"Android: {made}개 생성 → {dev_res.relative_to(ROOT)}")


if __name__ == "__main__":
    build_ios()
    build_android()
