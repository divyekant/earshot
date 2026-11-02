"""Render the earshot brand assets from the SVG sources in src/.

Usage (from assets/brand):
    uv run render.py                 # render all outputs from src/
    uv run render.py --wordmark FONT # also rebuild src/wordmark.svg from a font file

Outputs:
    AppIcon.svg, AppIcon.icns, AppIcon.iconset/, AppIcon.appiconset/,
    logo.svg, logo.png, logo-dark.svg, logo-dark.png, mark.svg, mark.png, preview.png
"""

import argparse
import io
import json
import shutil
from pathlib import Path

import cairosvg
from PIL import Image

HERE = Path(__file__).resolve().parent
SRC = HERE / "src"

INK = "#1B1340"  # wordmark color on a light background
BG_TOP = "#6A5CFF"
BG_BOTTOM = "#24166B"

# macOS icon sizes: (point size, scale).
ICON_SIZES = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]


def tile(defs_id: str, x: float, y: float, size: float, shadow: bool) -> tuple[str, str]:
    """Return (defs, body) for the rounded-square tile with the mark on it.

    The mark source uses a 1024 canvas where the tile is 824 wide at 100,100.
    """
    scale = size / 824
    defs = f"""
 <linearGradient id="{defs_id}-bg" x1="0" y1="0" x2="0.6" y2="1">
  <stop offset="0" stop-color="{BG_TOP}"/><stop offset="1" stop-color="{BG_BOTTOM}"/>
 </linearGradient>
 <filter id="{defs_id}-sh" x="-10%" y="-10%" width="120%" height="130%">
  <feDropShadow dx="0" dy="12" stdDeviation="14" flood-opacity="0.30"/>
 </filter>"""
    filt = f' filter="url(#{defs_id}-sh)"' if shadow else ""
    mark = (SRC / "mark.svg").read_text()
    body = f"""<g transform="translate({x} {y}) scale({scale}) translate(-100 -100)">
<rect x="100" y="100" width="824" height="824" rx="185" fill="url(#{defs_id}-bg)"{filt}/>
{mark}
</g>"""
    return defs, body


def svg_doc(w: float, h: float, defs: str, body: str) -> str:
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">\n'
        f"<defs>{defs}\n</defs>\n{body}\n</svg>\n"
    )


def png(svg: str, width: int, height: int | None = None) -> bytes:
    return cairosvg.svg2png(bytestring=svg.encode(), output_width=width, output_height=height or width)


def build_wordmark(font_path: Path) -> None:
    """Write src/wordmark.svg: "earshot" as outlines, so no font is needed later."""
    from fontTools.pens.svgPathPen import SVGPathPen
    from fontTools.pens.transformPen import TransformPen
    from fontTools.ttLib import TTFont

    font = TTFont(str(font_path))
    glyphs = font.getGlyphSet()
    cmap = font.getBestCmap()
    upm = font["head"].unitsPerEm
    x_height = font["OS/2"].sxHeight  # the wordmark is lower case
    k = 100 / x_height  # scale so that the x-height is 100 units
    tracking = -0.01 * upm
    x = 0.0
    parts = []
    for ch in "earshot":
        name = cmap[ord(ch)]
        pen = SVGPathPen(glyphs)
        glyphs[name].draw(TransformPen(pen, (k, 0, 0, -k, x * k, 0)))
        parts.append(pen.getCommands())
        x += glyphs[name].width + tracking
    width = (x - tracking) * k
    path = " ".join(parts)
    (SRC / "wordmark.svg").write_text(
        f'<!-- "earshot" in Inter Display SemiBold (SIL Open Font License), as outlines. '
        f'Baseline at y=0, x-height 100, width {width:.1f}. -->\n'
        f'<path id="wordmark" data-width="{width:.1f}" d="{path}"/>\n'
    )


def wordmark() -> tuple[str, float]:
    text = (SRC / "wordmark.svg").read_text()
    width = float(text.split('data-width="')[1].split('"')[0])
    path = text[text.index("<path"):].strip()
    return path, width


# ICNS element types that hold PNG data, with the pixel size of each.
ICNS_TYPES = [
    (b"icp4", 16), (b"icp5", 32), (b"ic11", 32), (b"ic12", 64), (b"ic07", 128),
    (b"ic13", 256), (b"ic08", 256), (b"ic14", 512), (b"ic09", 512), (b"ic10", 1024),
]


def write_icns(path: Path, by_px: dict[int, bytes]) -> None:
    """Write an .icns file with one PNG for each slot. iconutil is not needed."""
    body = b""
    for kind, px in ICNS_TYPES:
        data = by_px[px] if px in by_px else png((HERE / "AppIcon.svg").read_text(), px)
        body += kind + (8 + len(data)).to_bytes(4, "big") + data
    path.write_bytes(b"icns" + (8 + len(body)).to_bytes(4, "big") + body)


def logo(text_color: str) -> tuple[str, int, int]:
    """Horizontal logo: tile, then the wordmark. Returns (svg, width, height)."""
    word, word_w = wordmark()
    h = 240
    tile_size = 200
    gap = 44
    word_scale = 0.8  # x-height 80 units
    pad = 20
    defs, body = tile("logo", pad, pad, tile_size, shadow=False)
    baseline = pad + tile_size / 2 + 100 * word_scale / 2
    tx = pad + tile_size + gap
    w = int(tx + word_w * word_scale + pad)
    body += f'\n<g transform="translate({tx} {baseline}) scale({word_scale})" fill="{text_color}">{word}</g>'
    return svg_doc(w, h, defs, body), w, h


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--wordmark", type=Path, help="font file to rebuild src/wordmark.svg from")
    args = ap.parse_args()
    if args.wordmark:
        build_wordmark(args.wordmark)

    # App icon master (1024 canvas, tile with shadow).
    defs, body = tile("icon", 100, 100, 824, shadow=True)
    icon_svg = svg_doc(1024, 1024, defs, body)
    (HERE / "AppIcon.svg").write_text(icon_svg)

    iconset = HERE / "AppIcon.iconset"
    appiconset = HERE / "AppIcon.appiconset"
    for d in (iconset, appiconset):
        shutil.rmtree(d, ignore_errors=True)
        d.mkdir()
    images = []
    by_px: dict[int, bytes] = {}
    for pt, scale in ICON_SIZES:
        px = pt * scale
        data = by_px.setdefault(px, png(icon_svg, px))
        name = f"icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png"
        (iconset / name).write_bytes(data)
        (appiconset / name).write_bytes(data)
        images.append({"idiom": "mac", "size": f"{pt}x{pt}", "scale": f"{scale}x", "filename": name})
    (appiconset / "Contents.json").write_text(
        json.dumps({"images": images, "info": {"version": 1, "author": "xcode"}}, indent=2) + "\n"
    )

    write_icns(HERE / "AppIcon.icns", by_px)

    # Mark only, on its tile, no shadow (for docs and small places).
    defs, body = tile("mark", 0, 0, 512, shadow=False)
    mark_svg = svg_doc(512, 512, defs, body)
    (HERE / "mark.svg").write_text(mark_svg)
    (HERE / "mark.png").write_bytes(png(mark_svg, 512))

    # Logos for light and dark backgrounds.
    for name, color in (("logo", INK), ("logo-dark", "#FFFFFF")):
        svg, w, h = logo(color)
        (HERE / f"{name}.svg").write_text(svg)
        (HERE / f"{name}.png").write_bytes(png(svg, w * 2, h * 2))

    write_preview(icon_svg)


def write_preview(icon_svg: str) -> None:
    """One image for review: icon at several sizes, logo on light and dark."""
    w, h = 1600, 1000
    sheet = Image.new("RGBA", (w, h), "#F4F3F8")
    dark = Image.new("RGBA", (w, 300), "#15102E")
    sheet.paste(dark, (0, h - 300))
    x = 60
    for px in (512, 256, 128, 64, 32, 16):
        im = Image.open(io.BytesIO(png(icon_svg, px)))
        sheet.alpha_composite(im, (x, 20 + (512 - px) // 2))
        x += px + 50
    for name, y in (("logo", 535), ("logo-dark", h - 230)):
        svg, lw, lh = logo(INK if name == "logo" else "#FFFFFF")
        im = Image.open(io.BytesIO(png(svg, int(lw * 0.7), int(lh * 0.7))))
        sheet.alpha_composite(im, (60, y))
    sheet.convert("RGB").save(HERE / "preview.png")


if __name__ == "__main__":
    main()
