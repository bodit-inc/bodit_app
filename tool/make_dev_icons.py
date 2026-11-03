"""개발(dev) 빌드용 앱 아이콘을 만든다.

## 왜 스크립트인가

운영 아이콘이 바뀌면 개발 아이콘도 같이 바뀌어야 한다. 이미지를 손으로
편집해 커밋해두면 그때 한쪽만 낡는다 — 어느 쪽이 원본인지도 모르게 된다.
운영 아이콘을 **입력으로** 삼아 매번 다시 만든다.

## 무엇을 하나

운영 아이콘 **아래쪽**에 주황 띠와 흰 `dev` 글자를 얹는다.

한가운데에 얹었더니 로고를 통째로 덮어서 무슨 앱인지 알 수 없었다. 로고는
세로 가운데(iOS 기준 0.33~0.67)에 있고, 그 아래가 비어 있다. 띠를 그 빈
자리로 내리면 둘 다 보인다.

띠 위치는 타깃마다 다르다 — 캔버스에서 로고가 차지하는 자리가 다르고,
Android adaptive icon 은 런처가 원형으로 잘라내서 쓸 수 있는 범위가 더 좁다.

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

# 띠가 캔버스 높이에서 차지하는 구간 (위, 아래).
#
# 정사각 아이콘: 로고가 0.33~0.67 에 있으므로 그 아래. 바닥까지 붙이지 않는다 —
# 아래 `clip_to_alpha` 로 실루엣을 따라 잘리긴 하지만, 여백이 조금 있어야
# 띠가 "잘린 것" 이 아니라 "놓인 것" 으로 보인다.
BAND_SQUARE = (0.70, 0.93)

# Android adaptive icon 의 foreground: 런처가 **원형으로 잘라낸다.**
# 게다가 ic_launcher.xml 이 16% 를 더 인셋한다. 바닥 가까이 두면 잘려서
# 글자의 아랫부분이 사라진다. 로고(0.38~0.62) 바로 아래, 원 안에 머무는 범위.
BAND_ADAPTIVE = (0.66, 0.87)

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


def badge(
    src: Path,
    dst: Path,
    band: tuple[float, float],
    *,
    clip_to_alpha: bool,
) -> None:
    """`src` 아이콘 아래쪽에 dev 띠를 얹어 `dst` 로 저장한다.

    `clip_to_alpha` 는 띠를 **원본의 실루엣 안쪽으로만** 그린다. 모서리가
    둥글게 깎인 아이콘(Android 의 구형 mipmap)에서 띠가 투명한 모서리까지
    삐져나와 각진 덩어리가 되는 것을 막는다. 배경이 통째로 투명한
    adaptive foreground 에서는 쓰면 안 된다 — 띠가 남김없이 지워진다.
    """
    im = Image.open(src).convert("RGBA")
    w, h = im.size
    top, bottom = int(h * band[0]), int(h * band[1])

    # 띠는 별도 레이어에 그린다. 그래야 원본 알파로 잘라낼 수 있다.
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    draw.rectangle([0, top, w, bottom], fill=ORANGE)

    # 글자는 띠 높이에 맞춘다. 꽉 채우면 작은 크기에서 뭉개지므로 78%.
    band_h = bottom - top
    font = _font(max(8, int(band_h * 0.78)))
    # anchor="mm" = 중앙 정렬. 글자의 실제 잉크 기준이라 크기가 달라져도 안 흔들린다.
    draw.text((w / 2, (top + bottom) / 2), "dev", font=font, fill=WHITE, anchor="mm")

    if clip_to_alpha:
        layer.putalpha(Image.composite(
            layer.getchannel("A"),
            Image.new("L", (w, h), 0),
            im.getchannel("A").point(lambda v: 255 if v > 20 else 0),
        ))

    im.alpha_composite(layer)
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
        badge(png, dst_set / png.name, BAND_SQUARE, clip_to_alpha=True)
    print(f"iOS: {len(list(dst_set.glob('*.png')))}개 생성 → {dst_set.relative_to(ROOT)}")


def build_android() -> None:
    main_res = ROOT / "android/app/src/main/res"
    dev_res = ROOT / "android/app/src/dev/res"
    if dev_res.exists():
        shutil.rmtree(dev_res)

    made = 0
    for density in ("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi"):
        # 구형 런처가 쓰는 정사각 아이콘. 모서리가 깎여 있어 실루엣으로 자른다.
        legacy = main_res / f"mipmap-{density}/ic_launcher.png"
        if legacy.exists():
            badge(
                legacy,
                dev_res / f"mipmap-{density}/ic_launcher.png",
                BAND_SQUARE,
                clip_to_alpha=True,
            )
            made += 1
        # API 26+ 의 adaptive icon 은 이쪽을 본다. 여기를 안 덮으면 최신
        # 런처에서는 운영 아이콘이 그대로 뜬다 — 위 legacy 만으로는 모자라다.
        fg = main_res / f"drawable-{density}/ic_launcher_foreground.png"
        if fg.exists():
            badge(
                fg,
                dev_res / f"drawable-{density}/ic_launcher_foreground.png",
                BAND_ADAPTIVE,
                clip_to_alpha=False,
            )
            made += 1
    print(f"Android: {made}개 생성 → {dev_res.relative_to(ROOT)}")


if __name__ == "__main__":
    build_ios()
    build_android()
