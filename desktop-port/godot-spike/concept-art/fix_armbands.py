## 概念图臂章修正：AI 占位臂章 → 真 EDAA 徽记叠加（07 §3.3 工艺链：文字/徽记用 Pillow 确定性叠加）
## 雷暴图：全彩刺绣版徽记（作战单位）；浓雾图：黑白魔术贴版徽记（基准图样去色，§3.1 徽记层级）。
## 原图不改动，输出 *-armband-v2.jpg。
from PIL import Image, ImageEnhance, ImageFilter, ImageOps, ImageDraw
from pathlib import Path

BASE = Path(__file__).parent
EMBLEM_PATH = Path(__file__).resolve().parents[3] / "godot" / "assets" / "branding" / "edaa_emblem.png"


def load_emblem() -> Image.Image:
    return Image.open(EMBLEM_PATH).convert("RGBA")


def bw_emblem(emblem: Image.Image) -> Image.Image:
    """黑白魔术贴版：去色 + 对比度提升，保留黑底白线的魔术贴观感。"""
    gray = ImageOps.grayscale(emblem)
    gray = ImageOps.autocontrast(gray, cutoff=2)
    gray = ImageEnhance.Contrast(gray).enhance(1.35)
    return Image.merge("RGBA", (gray, gray, gray, emblem.split()[3]))


def paste_patch(img: Image.Image, patch: Image.Image, box, angle: float, squash: float,
                brightness: float, cover: bool = True, feather: int = 0) -> None:
    """box=(x0,y0,x1,y1) 目标臂章区域；cover=True 时先黑圆角块盖掉 AI 占位（白色护甲上的魔术贴章），
    cover=False 时直接贴（黑护甲上徽记黑底自融）；feather>0 时羽化徽记边缘融入底材。"""
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    if cover:
        cover_img = Image.new("RGBA", (int(w * 1.25), int(h * 1.25)), (0, 0, 0, 0))
        d = ImageDraw.Draw(cover_img)
        d.rounded_rectangle([0, 0, cover_img.width - 1, cover_img.height - 1], radius=int(w * 0.18),
                            fill=(8, 8, 10, 255))
        img.paste(cover_img, (int(x0 - w * 0.125), int(y0 - h * 0.125)), cover_img)
    # 徽记整形：横向压缩模拟侧面视角，再旋转
    p = patch.resize((int(w * squash), h), Image.LANCZOS)
    p = p.rotate(angle, expand=True, resample=Image.BICUBIC)
    if brightness < 1.0:
        rgb = p.convert("RGB")
        rgb = ImageEnhance.Brightness(rgb).enhance(brightness)
        p = Image.merge("RGBA", (*rgb.split(), p.split()[3]))
    if feather > 0:
        mask = Image.new("L", p.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, p.width - 1, p.height - 1],
                                               radius=int(min(p.size) * 0.3), fill=255)
        mask = mask.filter(ImageFilter.GaussianBlur(feather))
        alpha = p.split()[3]
        from PIL import ImageChops
        p = Image.merge("RGBA", (*p.convert("RGB").split(), ImageChops.multiply(alpha, mask)))
    px = x0 + (w - p.width) // 2
    py = y0 + (h - p.height) // 2
    img.paste(p, (px, py), p)


def main() -> None:
    emblem = load_emblem()
    emblem_bw = bw_emblem(emblem)

    # --- 雷暴：左肩甲外侧全彩刺绣臂章（黑护甲上黑底自融，不盖底、羽化边缘）---
    img1 = Image.open(BASE / "snuffers-01-thunderstorm-torch-concept.jpg").convert("RGBA")
    paste_patch(img1, emblem, box=(516, 252, 592, 318), angle=-10.0, squash=0.82, brightness=0.8,
                cover=False, feather=6)
    out1 = BASE / "snuffers-01-thunderstorm-torch-concept-armband-v2.jpg"
    img1.convert("RGB").save(out1, quality=92)

    # --- 浓雾：黑白魔术贴版 ×2（左人胸前臂章近乎正面；右人臂章微侧）---
    img2 = Image.open(BASE / "snuffers-02-densefog-armor-concept.jpg").convert("RGBA")
    paste_patch(img2, emblem_bw, box=(296, 366, 368, 444), angle=4.0, squash=0.95, brightness=0.85)
    paste_patch(img2, emblem_bw, box=(1610, 420, 1680, 488), angle=-6.0, squash=0.88, brightness=0.8)
    out2 = BASE / "snuffers-02-densefog-armor-concept-armband-v2.jpg"
    img2.convert("RGB").save(out2, quality=92)

    # 输出后整体轻微模糊融合一遍已不必要（JPEG 重编码自带融合），打印产物
    print(out1.name, out1.stat().st_size)
    print(out2.name, out2.stat().st_size)


if __name__ == "__main__":
    main()
