# earshot brand assets

This folder holds the earshot app icon and logo.

## The mark

The mark is an ear, drawn as one white stroke on a near-black tile.

- The ear is the same shape as the menu bar icon and the logo of the web site.
- The colors are the colors of the web site: white on near-black.

The tile is a superellipse (n = 5), the shape of a macOS icon.

## Files

| File | Use |
|---|---|
| `AppIcon.icns` | App bundle icon. Copy to `Contents/Resources/AppIcon.icns` and set `CFBundleIconFile` to `AppIcon`. |
| `AppIcon.appiconset/` | Xcode asset catalog icon set (all macOS sizes and `Contents.json`). |
| `AppIcon.iconset/` | Input for `iconutil -c icns AppIcon.iconset`, if you want to rebuild the `.icns` with Apple tools. |
| `AppIcon.svg` | Icon master, 1024 × 1024. |
| `mark.svg`, `mark.png` | The tile with the mark, no shadow, cropped to the tile, 512 × 512. |
| `glyph.svg`, `glyph.png` | The mark alone in one color (`currentColor` in the SVG), for the window header or the menu bar. |
| `social-preview.png` | GitHub social preview, 1280 × 640. Upload it in the repository settings, under Social preview. |
| `logo.svg`, `logo.png` | Tile and wordmark, for a light background. |
| `logo-dark.svg`, `logo-dark.png` | Tile and wordmark, for a dark background. |
| `preview.png` | Review sheet with all sizes. |
| `src/mark.svg` | Source of the mark (1024 canvas, tile at 100,100, 824 wide). The ear uses a 24-unit grid, scaled by 27. |
| `src/wordmark.svg` | "earshot" as outlines. |

## Colors

| Name | Value |
|---|---|
| Tile top | `#2C2C29` |
| Tile bottom | `#0C0C0B` |
| Ear | `#F2F2EE` |
| Ink (wordmark on light) | `#161615` |

`app/Sources/EarshotUI/Brand.swift` uses the same colors and the same ear curves.

## Rebuild

Edit `src/mark.svg`, then run:

```sh
cd assets/brand
uv run render.py
```

The script needs no Apple tools. It writes the `.icns` file directly.

To rebuild the wordmark from a font file:

```sh
uv run render.py --wordmark /path/to/InterDisplay-Bold.otf
```

## Font

The wordmark uses Inter Display Bold, as outlines. Inter is under the SIL Open Font License 1.1. The SVG and PNG files do not need the font.
