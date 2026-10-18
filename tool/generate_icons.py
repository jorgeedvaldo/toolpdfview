#!/usr/bin/env python3
"""Generates the ToolPDF View launcher icon source images.

Run it after changing the brand colours, then regenerate the Android
launcher resources with:  dart run flutter_launcher_icons
"""
from PIL import Image, ImageDraw, ImageFont

SIZE = 1024
RED = (211, 47, 47, 255)        # #D32F2F
WHITE = (255, 255, 255, 255)
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


def draw_mark(draw: ImageDraw.ImageDraw, cx: float, cy: float, scale: float) -> None:
    """Draws the white outlined PDF sheet centred on (cx, cy)."""
    w, h = 470 * scale, 620 * scale
    fold = 150 * scale
    stroke = max(2, int(42 * scale))
    x0, y0 = cx - w / 2, cy - h / 2
    x1, y1 = cx + w / 2, cy + h / 2

    page = [(x0, y0), (x1 - fold, y0), (x1, y0 + fold), (x1, y1), (x0, y1)]
    # repeat the first two points so the closing corner is mitred like the others
    draw.line(page + [page[0], page[1]], fill=WHITE, width=stroke, joint="curve")
    # folded corner
    draw.line(
        [(x1 - fold, y0), (x1 - fold, y0 + fold), (x1, y0 + fold)],
        fill=WHITE,
        width=stroke,
        joint="curve",
    )
    # "PDF" wordmark
    font = ImageFont.truetype(FONT, int(132 * scale))
    label = "PDF"
    box = draw.textbbox((0, 0), label, font=font)
    draw.text(
        (cx - (box[2] - box[0]) / 2 - box[0], cy + 70 * scale - (box[3] - box[1]) / 2 - box[1]),
        label,
        font=font,
        fill=WHITE,
    )


def rounded_red() -> Image.Image:
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, SIZE - 1, SIZE - 1], radius=190, fill=RED)
    return img


def main() -> None:
    # 1. Full icon (legacy launcher, store listing, in-app branding)
    full = rounded_red()
    draw_mark(ImageDraw.Draw(full), SIZE / 2, SIZE / 2, 1.0)
    full.save("assets/icon/icon.png")

    # 2. Adaptive foreground: content stays inside the 66% safe zone
    fg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw_mark(ImageDraw.Draw(fg), SIZE / 2, SIZE / 2, 0.62)
    fg.save("assets/icon/icon_foreground.png")

    # 3. Play Store listing icon (512x512, opaque)
    store = Image.new("RGB", (512, 512), RED[:3])
    store.paste(full.resize((512, 512), Image.LANCZOS), (0, 0), full.resize((512, 512), Image.LANCZOS))
    store.save("assets/icon/play_store_512.png")

    print("icons written to assets/icon/")


if __name__ == "__main__":
    main()
