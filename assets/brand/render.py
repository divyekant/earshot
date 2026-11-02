"""Render the earshot brand assets from the SVG sources in src/.

Usage (from assets/brand):
    uv run render.py                 # render all outputs from src/
    uv run render.py --wordmark FONT # also rebuild src/wordmark.svg from a font file

Outputs:
    AppIcon.svg, AppIcon.icns, AppIcon.iconset/, AppIcon.appiconset/,
    mark.svg, mark.png, glyph.svg, glyph.png,
    logo.svg, logo.png, logo-dark.svg, logo-dark.png, preview.png
"""

import argparse
import io
import json
import math
import shutil
from pathlib import Path

import cairosvg
from PIL import Image

HERE = Path(__file__).resolve().parent
SRC = HERE / "src"

# Colors. README.md lists the same values.
BG_TOP = "#3A2FA8"
BG_BOTTOM = "#0E0B2E"
BAR_BOTTOM = "#C4BAFF"
CURSOR_TOP = "#FFD978"
CURSOR_BOTTOM = "#FF9A3C"
INK = "#14112E"  # wordmark on a light background

# macOS icon sizes: (point size, scale).
ICON_SIZES = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]

# ICNS element types that hold PNG data, with the pixel size of each.
ICNS_TYPES = [
    (b"icp4", 16), (b"icp5", 32), (b"ic11", 32), (b"ic12", 64), (b"ic07", 128),
    (b"ic13", 256), (b"ic08", 256), (b"ic14", 512), (b"ic09", 512), (b"ic10", 1024),
]


def squircle(x: float, y: float, size: float, n: float = 5.0, steps: int = 256) -> str:
    """Path data for a superellipse |x|^n + |y|^n = 1, the macOS icon shape."""
    r = size / 2
    cx, cy = x + r, y + r
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        px = cx + r * math.copysign(abs(c) ** (2 / n), c)
        py = cy + r * math.copysign(abs(s) ** (2 / n), s)
        pts.append(f"{px:.2f} {py:.2f}")
    return "M " + " L ".join(pts) + " Z"


TILE = squircle(100, 100, 824)


def defs(shadow: bool) -> str:
    out = f"""
 <linearGradient id="bg" x1="0.15" y1="0" x2="0.85" y2="1">
  <stop offset="0" stop-color="{BG_TOP}"/><stop offset="1" stop-color="{BG_BOTTOM}"/>
 </linearGradient>
 <radialGradient id="highlight" cx="0.3" cy="0.12" r="0.75">
  <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.18"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
 </radialGradient>
 <linearGradient id="bar" gradientUnits="userSpaceOnUse" x1="0" y1="286" x2="0" y2="738">
  <stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="{BAR_BOTTOM}"/>
 </linearGradient>
 <linearGradient id="cursor" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="{CURSOR_TOP}"/><stop offset="1" stop-color="{CURSOR_BOTTOM}"/>
 </linearGradient>
 <filter id="cursor-glow" x="-150%" y="-20%" width="400%" height="140%"><feGaussianBlur stdDeviation="16"/></filter>
 <clipPath id="tile-clip"><path d="{TILE}"/></clipPath>"""
    if shadow:
        out += """
 <filter id="shadow" x="-10%" y="-10%" width="120%" height="130%">
  <feDropShadow dx="0" dy="14" stdDeviation="16" flood-color="#0B0630" flood-opacity="0.35"/>
 </filter>"""
    return out


def tile_body(shadow: bool) -> str:
    """The tile and the mark on the 1024 canvas (tile at 100,100, 824 wide)."""
    filt = ' filter="url(#shadow)"' if shadow else ""
    mark = (SRC / "mark.svg").read_text()
    return f"""<path d="{TILE}" fill="url(#bg)"{filt}/>
<g clip-path="url(#tile-clip)"><rect x="100" y="100" width="824" height="824" fill="url(#highlight)"/>
{mark}
</g>
<path d="{TILE}" fill="none" stroke="#FFFFFF" stroke-opacity="0.16" stroke-width="3" transform="translate(512 512) scale(0.9964) translate(-512 -512)"/>"""


def svg_doc(w: float, h: float, view: str, inner: str) -> str:
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="{view}">\n'
        f"{inner}\n</svg>\n"
    )


def png(svg: str, width: int, height: int | None = None) -> bytes:
    return cairosvg.svg2png(bytestring=svg.encode(), output_width=width, output_height=height or width)


def icon_svg() -> str:
    return svg_doc(1024, 1024, "0 0 1024 1024", f"<defs>{defs(True)}\n</defs>\n{tile_body(True)}")


def mark_svg() -> str:
    """The tile with the mark, cropped to the tile, no shadow."""
    return svg_doc(512, 512, "100 100 824 824", f"<defs>{defs(False)}\n</defs>\n{tile_body(False)}")


def glyph_svg(color: str = "currentColor") -> str:
    """The mark alone in one color, for UI use (menu bar, window header)."""
    mark = (SRC / "mark.svg").read_text()
    mark = mark.replace('fill="url(#bar)"', f'fill="{color}"').replace('fill="url(#cursor)"', f'fill="{color}"')
    mark = "\n".join(line for line in mark.splitlines() if "cursor-glow" not in line)
    return svg_doc(472, 452, "276 286 472 452", mark)


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
    tracking = -0.02 * upm
    x = 0.0
    parts = []
    for ch in "earshot":
        name = cmap[ord(ch)]
        pen = SVGPathPen(glyphs)
        glyphs[name].draw(TransformPen(pen, (k, 0, 0, -k, x * k, 0)))
        parts.append(pen.getCommands())
        x += glyphs[name].width + tracking
    width = (x - tracking) * k
    (SRC / "wordmark.svg").write_text(
        f'<!-- "earshot" in {font_path.stem} (SIL Open Font License), as outlines. '
        f"Baseline at y=0, x-height 100, width {width:.1f}. -->\n"
        f'<path id="wordmark" data-width="{width:.1f}" d="{" ".join(parts)}"/>\n'
    )


def wordmark() -> tuple[str, float]:
    text = (SRC / "wordmark.svg").read_text()
    width = float(text.split('data-width="')[1].split('"')[0])
    return text[text.index("<path"):].strip(), width


def logo(text_color: str) -> tuple[str, int, int]:
    """Horizontal logo: tile, then the wordmark. Returns (svg, width, height)."""
    word, word_w = wordmark()
    pad, tile_size, gap, word_scale = 16, 208, 44, 0.78
    h = tile_size + 2 * pad
    s = tile_size / 824
    baseline = pad + tile_size / 2 + 100 * word_scale / 2
    tx = pad + tile_size + gap
    w = int(tx + word_w * word_scale + pad)
    inner = (
        f"<defs>{defs(False)}\n</defs>\n"
        f'<g transform="translate({pad} {pad}) scale({s}) translate(-100 -100)">{tile_body(False)}</g>\n'
        f'<g transform="translate({tx} {baseline}) scale({word_scale})" fill="{text_color}">{word}</g>'
    )
    return svg_doc(w, h, f"0 0 {w} {h}", inner), w, h


def write_icns(path: Path, by_px: dict[int, bytes], svg: str) -> None:
    """Write an .icns file with one PNG for each slot. iconutil is not needed."""
    body = b""
    for kind, px in ICNS_TYPES:
        data = by_px[px] if px in by_px else png(svg, px)
        body += kind + (8 + len(data)).to_bytes(4, "big") + data
    path.write_bytes(b"icns" + (8 + len(body)).to_bytes(4, "big") + body)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--wordmark", type=Path, help="font file to rebuild src/wordmark.svg from")
    args = ap.parse_args()
    if args.wordmark:
        build_wordmark(args.wordmark)

    icon = icon_svg()
    (HERE / "AppIcon.svg").write_text(icon)

    iconset = HERE / "AppIcon.iconset"
    appiconset = HERE / "AppIcon.appiconset"
    for d in (iconset, appiconset):
        shutil.rmtree(d, ignore_errors=True)
        d.mkdir()
    images = []
    by_px: dict[int, bytes] = {}
    for pt, scale in ICON_SIZES:
        px = pt * scale
        data = by_px.setdefault(px, png(icon, px))
        name = f"icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png"
        (iconset / name).write_bytes(data)
        (appiconset / name).write_bytes(data)
        images.append({"idiom": "mac", "size": f"{pt}x{pt}", "scale": f"{scale}x", "filename": name})
    (appiconset / "Contents.json").write_text(
        json.dumps({"images": images, "info": {"version": 1, "author": "xcode"}}, indent=2) + "\n"
    )
    write_icns(HERE / "AppIcon.icns", by_px, icon)

    mark = mark_svg()
    (HERE / "mark.svg").write_text(mark)
    (HERE / "mark.png").write_bytes(png(mark, 512))

    (HERE / "glyph.svg").write_text(glyph_svg())
    (HERE / "glyph.png").write_bytes(png(glyph_svg("#000000"), 236, 226))

    for name, color in (("logo", INK), ("logo-dark", "#FFFFFF")):
        svg, w, h = logo(color)
        (HERE / f"{name}.svg").write_text(svg)
        (HERE / f"{name}.png").write_bytes(png(svg, w * 2, h * 2))

    write_preview(icon)


def write_preview(icon: str) -> None:
    """One image for review: icon at several sizes, logo on light and dark."""
    w, h = 1600, 1000
    sheet = Image.new("RGBA", (w, h), "#F4F3F8")
    sheet.paste(Image.new("RGBA", (w, 270), "#100D26"), (0, h - 270))
    x = 50
    for px in (512, 256, 128, 64, 32, 16):
        im = Image.open(io.BytesIO(png(icon, px)))
        sheet.alpha_composite(im, (x, 40 + (512 - px) // 2))
        x += px + 50
    for name, color, y in (("logo", INK, 545), ("logo-dark", "#FFFFFF", h - 225)):
        svg, lw, lh = logo(color)
        im = Image.open(io.BytesIO(png(svg, int(lw * 0.75), int(lh * 0.75))))
        sheet.alpha_composite(im, (60, y))
    for i, color in enumerate(("#14112E", "#FFFFFF")):
        im = Image.open(io.BytesIO(png(glyph_svg(color), 118, 113)))
        sheet.alpha_composite(im, (1400, 578 + i * 270))
    sheet.convert("RGB").save(HERE / "preview.png")


if __name__ == "__main__":
    main()
