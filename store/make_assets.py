"""
make_assets.py - Connect IQ 스토어용 이미지 생성 (zzGradePlus)

    python store/make_assets.py          -> store/images/*.png

  cover.png          대표 이미지 500x500 (앱 아이콘, 투명 배경)
  hero_en.png        히어로 1440x720 (영어)
  screen{1..5}.png   동작 화면 500x500 (영어). 기기별·칸 크기별 5장

화면 속 데이터 필드는 앱과 같은 비트맵 폰트(fonts/fWxH/*.fnt)를 읽어
앱의 onLayout / drawCell10 / drawWide 와 같은 계산으로 그린다.
Pillow 필요.
"""
import os
import re

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
FONTDIR = os.path.join(ROOT, "fonts")
OUT = os.path.join(HERE, "images")
os.makedirs(OUT, exist_ok=True)

TITILLIUM = os.path.join(ROOT, "tools", "ttf", "TitilliumWeb-Bold.ttf")
if not os.path.exists(TITILLIUM):                       # 저장소에 없으면 시스템 글꼴
    for c in ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
              "C:/Windows/Fonts/segoeuib.ttf"]:
        if os.path.exists(c):
            TITILLIUM = c
            break


def ti(size):
    return ImageFont.truetype(TITILLIUM, size)


# ---------------------------------------------------------------- 비트맵 폰트
class BMFont:
    """앱이 쓰는 .fnt + .png 를 그대로 읽어 글자를 찍는다."""

    def __init__(self, fnt):
        t = open(fnt, encoding="utf-8").read()
        lines = t.splitlines()
        self.base = int(re.search(r"base=(\d+)", lines[1]).group(1))
        self.line = int(re.search(r"lineHeight=(\d+)", lines[1]).group(1))
        page = re.search(r'file="([^"]+)"', lines[2]).group(1)
        self.sheet = Image.open(os.path.join(os.path.dirname(fnt), page)).convert("L")
        self.ch = {}
        for m in re.finditer(
            r"char id=(\d+) x=(\d+) y=(\d+) width=(\d+) height=(\d+) "
            r"xoffset=(-?\d+) yoffset=(-?\d+) xadvance=(-?\d+)", t):
            c, x, y, w, h, xo, yo, xa = (int(g) for g in m.groups())
            self.ch.setdefault(c, dict(x=x, y=y, w=w, h=h, xo=xo, yo=yo, xa=xa))

    def width(self, s):
        return sum(self.ch[ord(c)]["xa"] for c in s if ord(c) in self.ch)

    def draw(self, img, x, y, s, color, justify="left"):
        """y 는 Monkey C 와 같게 글자 줄의 윗변."""
        w = self.width(s)
        pen = x - w if justify == "right" else (x - w // 2 if justify == "center" else x)
        for c in s:
            g = self.ch.get(ord(c))
            if g is None:
                continue
            mask = self.sheet.crop((g["x"], g["y"], g["x"] + g["w"], g["y"] + g["h"]))
            img.paste(Image.new("RGB", mask.size, color), (pen + g["xo"], y + g["yo"]), mask)
            pen += g["xa"]


def load_fonts(folder):
    d = os.path.join(FONTDIR, folder)
    xml = open(os.path.join(d, "fonts.xml"), encoding="utf-8").read()
    out = {}
    for fid, fn in re.findall(r'id="([^"]+)" filename="([^"]+)"', xml):
        out[fid] = BMFont(os.path.join(d, fn))
    return out


# ---------------------------------------------------------------- 값 / 색
GRADE, ALT, ASC, LAP, NONE = range(5)
NAME = ["%", "ALT ", "ASC ", "LAP ", ""]

COLORS = [0, 0xFF0000, 0xFF55AA, 0xFF00FF, 0xFF5500,
          0xFFAA00, 0x00AA00, 0x00AAFF, 0x0000FF, 0xAA00FF]


def rgb(v):
    return ((v >> 16) & 255, (v >> 8) & 255, v & 255)


DAY_HIGH, DAY_LOW = rgb(COLORS[1]), rgb(COLORS[8])        # 빨강 / 진한 파랑
NIGHT_HIGH, NIGHT_LOW = rgb(COLORS[2]), rgb(COLORS[7])    # 분홍 / 하늘
THR10 = 10                                                # 기본 1 %


def grade_parts(g10):
    sign = "-" if g10 < 0 else ""
    a = abs(g10)
    if a < 100:
        return sign + str(a // 10), "." + str(a % 10)
    return sign + str((a + 5) // 10), ""


# ---------------------------------------------------------------- 한 칸 그리기
def draw_cell(img, box, F, screen_w, cell, night, unit="m"):
    """cell = dict(main=, second=, g10=, v=, v2=)  — 앱의 draw 로직과 같게."""
    x0, y0, w, h = box
    fg = (255, 255, 255) if night else (0, 0, 0)
    ic = rgb(0x00FF00) if night else rgb(0x00AA00)
    hi = NIGHT_HIGH if night else DAY_HIGH
    lo = NIGHT_LOW if night else DAY_LOW

    g10 = cell["g10"]
    mc = fg
    if g10 > THR10:
        mc = hi
    elif g10 < -THR10:
        mc = lo
    gi, gd = grade_parts(g10)
    gs = gi + gd

    main, second = cell["main"], cell["second"]
    mains = str(cell.get("v", 0))
    subs = str(cell.get("v2", 0))

    L = int(w * 0.05 + 0.5)
    T = int(h * 0.05 + 0.5)
    R = w - L
    B = h - T
    wide = w > screen_w * 0.75

    if not wide:
        fMain, fDec = F["C10Main"], F["C10MainDec"]
        fSub, fUM, fUS = F["C10Sub"], F["C10UnitMain"], F["C10UnitSub"]
        ug = max(2, int(w * 0.02))
        yMain = B - fMain.base
        yDec = yMain + fMain.base - fDec.base
        xMainG = R - fUM.width("%") - ug
        xMainA = R - fUM.width("ft") - ug
        wDec = fDec.width(".0")
        xSubA = R - fUS.width("ft") - ug
        xSubG = R - fUS.width("%") - ug
        xSubMax4 = xSubA - fSub.width("8888") - fSub.width("@")

        if main == GRADE:
            x = xMainG
            if gd:
                fDec.draw(img, x0 + x, y0 + yDec, gd, mc, "right")
                x -= wDec
            fMain.draw(img, x0 + x, y0 + yMain, gi, mc, "right")
            fUM.draw(img, x0 + R, y0 + yMain, "%", fg, "right")
        else:
            if len(mains) >= 5:
                fDec.draw(img, x0 + xMainA, y0 + yDec, mains, fg, "right")
            else:
                fMain.draw(img, x0 + xMainA, y0 + yMain, mains, fg, "right")
            fUM.draw(img, x0 + R, y0 + yMain, unit, fg, "right")

        tops = gs if second == GRADE else ("" if second == NONE else subs)
        if len(tops) < 5:
            fSub.draw(img, x0 + L, y0 + T, "@", ic)
        if second == NONE:
            return
        if second == GRADE:
            fSub.draw(img, x0 + xSubG, y0 + T, gs, mc, "right")
            fUS.draw(img, x0 + R, y0 + T, "%", fg, "right")
            return
        if len(tops) < 4 or xSubMax4 >= L:
            fSub.draw(img, x0 + xSubA, y0 + T, subs, fg, "right")
            fUS.draw(img, x0 + R, y0 + T, unit, fg, "right")
        else:
            fSub.draw(img, x0 + R, y0 + T, subs, fg, "right")
        return

    # ---- 넓은 칸 ----
    fTitle, fLabel = F["WideTitle"], F["WideLabel"]
    fVal, fVal5 = F["WideVal"], F["WideVal5"]
    gap = max(4, int(w * 0.04))
    vg = max(2, int(h * 0.05))
    hu = B - T
    title_on = (hu - fTitle.line - vg) >= fVal.base
    top = T
    if title_on:
        xTitle = L + fTitle.width("@")
        wTitle = fTitle.width("zzGrade+")
        yLabel = T + fTitle.base - fLabel.base
        label = (NAME[main] + (unit if main else "")).strip()
        if second != NONE:
            label += "  /  " + (NAME[second] + (unit if second else "")).strip()
        fTitle.draw(img, x0 + L, y0 + T, "@", ic)
        lw = fLabel.width(label)
        fLabel.draw(img, x0 + R, y0 + yLabel, label, (85, 85, 85) if not night else (170, 170, 170), "right")
        if xTitle + wTitle + 6 <= R - lw:
            fTitle.draw(img, x0 + xTitle, y0 + T, "zzGrade+", fg)
        top = T + fTitle.line + vg

    yVal = top + (B - top - fVal.base) // 2
    yVal5 = yVal + fVal.base - fVal5.base
    mid = w // 2
    xc1 = (L + mid - gap // 2) // 2
    xc2 = (mid + gap // 2 + R) // 2

    def val(xc, s, col):
        if len(s) >= 5:
            fVal5.draw(img, x0 + xc, y0 + yVal5, s, col, "center")
        else:
            fVal.draw(img, x0 + xc, y0 + yVal, s, col, "center")

    mains_txt = gs if main == GRADE else mains
    if second == NONE:
        val(mid, mains_txt, mc if main == GRADE else fg)
        return
    val(xc1, mains_txt, mc if main == GRADE else fg)
    val(xc2, gs if second == GRADE else subs, mc if second == GRADE else fg)
    d = ImageDraw.Draw(img)
    line = (90, 90, 90) if night else (190, 190, 190)
    d.line([(x0 + mid, y0 + top), (x0 + mid, y0 + B)], fill=line, width=1)


# ---------------------------------------------------------------- 화면 / 본체
def render_screen(res, cells, night=False, unit="m"):
    w, h = res
    folder = "f%dx%d" % res
    F = load_fonts(folder)
    bg = (0, 0, 0) if night else (255, 255, 255)
    img = Image.new("RGB", (w, h), bg)
    d = ImageDraw.Draw(img)
    grid = (0, 120, 215)
    for box, cell in cells:
        draw_cell(img, box, F, w, cell, night, unit)
    for box, _ in cells:
        x0, y0, cw, ch = box
        d.rectangle([x0, y0, x0 + cw - 1, y0 + ch - 1], outline=grid, width=1)
    return img


def device(screen, side=16, top=22, bottom=30, radius=26):
    sw, sh = screen.size
    W, H = sw + side * 2, sh + top + bottom
    ss = 3
    body = Image.new("RGBA", (W * ss, H * ss), (0, 0, 0, 0))
    ImageDraw.Draw(body).rounded_rectangle(
        [0, 0, W * ss - 1, H * ss - 1], radius=radius * ss, fill=(34, 34, 36, 255))
    body = body.resize((W, H), Image.LANCZOS)
    body.paste(screen, (side, top))
    ImageDraw.Draw(body).rectangle(
        [side - 1, top - 1, side + sw, top + sh], outline=(70, 70, 74, 255), width=1)
    return body


def fit(img, box_w, box_h):
    k = min(box_w / img.width, box_h / img.height)
    return img.resize((max(1, int(img.width * k)), max(1, int(img.height * k))), Image.LANCZOS)


# ---------------------------------------------------------------- 화면 구성
def grid_cells(res, rows, cols, top_full=False):
    """화면을 rows x cols 로 자른다. top_full 이면 맨 윗줄은 전폭 한 칸."""
    w, h = res
    boxes = []
    y = 0
    n = rows + (1 if top_full else 0)
    hh = h // n
    if top_full:
        boxes.append((0, 0, w, hh))
        y = hh
    for r in range(rows):
        ch = h - y if r == rows - 1 else hh
        cw = w // cols
        for c in range(cols):
            x = c * cw
            boxes.append((x, y, (w - x) if c == cols - 1 else cw, ch))
        y += ch
    return boxes


def C(main, second, g10, v=0, v2=0):
    return dict(main=main, second=second, g10=g10, v=v, v2=v2)


SCREENS = [
    dict(name="screen1",
         title="Grade and altitude in every slot",
         sub="Edge 1050 / 1060 \u00b7 10-field layout",
         res=(480, 800), rows=5, cols=2, night=False,
         cells=[C(GRADE, ASC, 74, v2=1234), C(GRADE, ALT, 130, v2=1240),
                C(GRADE, ASC, -42, v2=1180), C(GRADE, ALT, 31, v2=980),
                C(GRADE, LAP, 4, v2=1022), C(GRADE, ASC, 98, v2=1488),
                C(GRADE, ALT, -110, v2=1350), C(GRADE, ASC, 55, v2=864),
                C(GRADE, ALT, 18, v2=1102), C(GRADE, ASC, -6, v2=1006)]),

    dict(name="screen2",
         title="Put altitude in the large digits",
         sub="Edge 1050 / 1060 \u00b7 10-field layout",
         res=(480, 800), rows=5, cols=2, night=False,
         cells=[C(ALT, GRADE, 74, v=1234), C(ASC, GRADE, 130, v=1240),
                C(ALT, GRADE, -42, v=1180), C(ASC, GRADE, 31, v=980),
                C(ALT, ASC, 4, v=1022, v2=1488), C(ASC, LAP, 98, v=1488, v2=240),
                C(GRADE, NONE, -110), C(ALT, NONE, 55, v=864),
                C(GRADE, ASC, 18, v2=1102), C(LAP, GRADE, -6, v=206)]),

    dict(name="screen3",
         title="Wide slots show both values side by side",
         sub="Edge 1050 / 1060 \u00b7 2-field layout",
         res=(480, 800), rows=3, cols=1, night=False,
         cells=[C(GRADE, ASC, 74, v2=1234),
                C(ALT, GRADE, -42, v=1180),
                C(ALT, ASC, 130, v=1240, v2=2480)]),

    dict(name="screen4",
         title="Night mode follows your device",
         sub="Edge 1040 \u00b7 10-field layout",
         res=(282, 470), rows=5, cols=2, night=True,
         cells=[C(GRADE, ASC, 74, v2=1234), C(ALT, GRADE, 130, v=1240),
                C(GRADE, ALT, -42, v2=1180), C(GRADE, ASC, 31, v2=980),
                C(ASC, GRADE, 4, v=1022), C(GRADE, LAP, 98, v2=148),
                C(GRADE, ALT, -110, v2=1350), C(GRADE, ASC, 55, v2=864),
                C(ALT, GRADE, 18, v=1102), C(GRADE, ASC, -6, v2=1006)]),

    dict(name="screen5",
         title="Fits every Edge, from 540 to 1060",
         sub="Edge 540 / 840 \u00b7 7-field layout",
         res=(246, 322), rows=3, cols=2, top_full=True, night=False,
         cells=[C(GRADE, ASC, 74, v2=1234),
                C(GRADE, ALT, 130, v2=1240), C(ALT, GRADE, -42, v=1180),
                C(GRADE, ASC, 31, v2=980), C(ASC, GRADE, 98, v=1488),
                C(GRADE, LAP, 4, v2=102), C(GRADE, ALT, -110, v2=1350)]),
]


def make_screens():
    for s in SCREENS:
        boxes = grid_cells(s["res"], s["rows"], s["cols"], s.get("top_full", False))
        cells = list(zip(boxes, s["cells"]))
        scr = render_screen(s["res"], cells, s["night"])
        dev = device(scr)

        card = Image.new("RGB", (500, 500), (240, 242, 247))
        d = ImageDraw.Draw(card)
        d.text((250, 26), s["title"], font=ti(23), fill=(24, 28, 38), anchor="mt")
        d.text((250, 60), s["sub"], font=ti(15), fill=(96, 104, 120), anchor="mt")
        dev = fit(dev, 420, 392)
        card.paste(dev, ((500 - dev.width) // 2, 92 + (392 - dev.height) // 2))
        card.save(os.path.join(OUT, s["name"] + ".png"), optimize=True)
        print("  %s.png  %s  %dx%d" % (s["name"], s["sub"], *s["res"]))


# ---------------------------------------------------------------- 아이콘 / 커버
def icon(size, color=(0, 150, 60)):
    """런처 아이콘과 같은 산 모양."""
    p = os.path.join(ROOT, "resources-edge1050", "drawables", "launcher_icon.png")
    if not os.path.exists(p):
        p = os.path.join(ROOT, "resources", "drawables", "launcher_icon.png")
    im = Image.open(p).convert("RGBA")
    im = im.resize((size, size), Image.LANCZOS)
    solid = Image.new("RGBA", im.size, color + (255,))
    solid.putalpha(im.getchannel("A"))
    return solid


def card(size, cell, native=(240, 160), radius=28, res=(480, 800), screen_w=4000):
    """흰 둥근 카드 안에 데이터 필드 한 칸.

    기기의 실제 칸 크기(native, 1050/1060 의 10칸 = 240x160)로 그린 뒤
    카드 크기로 확대한다. 그래야 숫자가 기기에서 보이는 비율 그대로 커 보인다.
    """
    w, h = size
    nw, nh = native
    F = load_fonts("f%dx%d" % res)
    inner = Image.new("RGB", (nw, nh), (255, 255, 255))
    draw_cell(inner, (0, 0, nw, nh), F, screen_w, cell, False)
    inner = inner.resize((w, h), Image.LANCZOS)
    ss = 3
    mask = Image.new("L", (w * ss, h * ss), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, w * ss - 1, h * ss - 1], radius=radius * ss, fill=255)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.paste(inner, (0, 0), mask.resize((w, h), Image.LANCZOS))
    return out


def make_cover():
    """zzGradePlus_cover_500x500.png 형식 - 어두운 배경 + 흰 카드 + 앱 이름."""
    c = Image.new("RGB", (500, 500), (26, 31, 40))
    cd = card((420, 280), C(GRADE, ASC, 63, v2=1234))
    c.paste(cd, (40, 52), cd)
    d = ImageDraw.Draw(c)
    d.text((250, 358), "zzGradePlus", font=ti(52), fill=(255, 255, 255), anchor="mt")
    d.text((250, 434), "GRADE  /  ALT  /  ASCENT", font=ti(24),
           fill=(118, 214, 152), anchor="mt")
    c.save(os.path.join(OUT, "cover.png"), optimize=True)
    print("  cover.png  500x500")


# ---------------------------------------------------------------- 히어로
def make_hero():
    W, H = 1440, 720
    hero = Image.new("RGB", (W, H), (13, 20, 16))
    # 왼쪽 아래에서 번지는 초록빛
    glow = Image.new("RGB", (W, H), (13, 20, 16))
    ImageDraw.Draw(glow).ellipse([-200, 120, 900, 1000], fill=(16, 54, 32))
    hero = Image.blend(hero, glow.filter(ImageFilter.GaussianBlur(160)), 1.0)
    d = ImageDraw.Draw(hero)

    g = icon(74)
    hero.paste(g, (96, 92), g)
    d.text((96, 186), "Garmin Edge data field", font=ti(30), fill=(150, 165, 155))
    d.text((96, 240), "zzGradePlus", font=ti(96), fill=(255, 255, 255))
    d.text((96, 364), "Grade \u00b7 Altitude \u00b7 Ascent \u00b7 Lap ascent",
           font=ti(30), fill=(226, 232, 228))
    bullets = ["Climbs and descents in color, instantly",
               "Real grade right after you start again",
               "Grade saved to your activity"]
    y = 438
    for b in bullets:
        d.ellipse([97, y + 9, 109, y + 21], fill=(70, 200, 120))
        d.text((128, y), b, font=ti(26), fill=(214, 222, 216))
        y += 54
    d.text((96, 634), "Edge 540 \u00b7 550 \u00b7 840 \u00b7 850 \u00b7 1040 \u00b7 1050 \u00b7 1060",
           font=ti(24), fill=(120, 136, 126))

    # 오른쪽 기기 두 대
    s1 = SCREENS[0]
    scr1 = render_screen(s1["res"], list(zip(grid_cells(s1["res"], 5, 2), s1["cells"])), False)
    d1 = fit(device(scr1), 330, 548)
    s2 = SCREENS[3]
    scr2 = render_screen(s2["res"], list(zip(grid_cells(s2["res"], 5, 2), s2["cells"])), True)
    d2 = fit(device(scr2), 278, 458)

    def shadow(dst, im, pos):
        sh = Image.new("RGBA", (im.width + 80, im.height + 80), (0, 0, 0, 0))
        ImageDraw.Draw(sh).rounded_rectangle(
            [40, 46, 40 + im.width, 46 + im.height], radius=26, fill=(0, 0, 0, 150))
        sh = sh.filter(ImageFilter.GaussianBlur(22))
        dst.paste(Image.alpha_composite(
            dst.crop((pos[0] - 40, pos[1] - 40, pos[0] - 40 + sh.width, pos[1] - 40 + sh.height))
               .convert("RGBA"), sh).convert("RGB"), (pos[0] - 40, pos[1] - 40))
        dst.paste(im, pos)

    shadow(hero, d1.convert("RGB"), (1068, 86))
    shadow(hero, d2.convert("RGB"), (812, 196))
    hero.save(os.path.join(OUT, "hero_en.png"), optimize=True)
    print("  hero_en.png  1440x720")


if __name__ == "__main__":
    print("zzGradePlus 스토어 이미지")
    make_cover()
    make_screens()
    make_hero()
    print("-> " + OUT)
