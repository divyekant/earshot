# earshot brand assets

This folder holds the earshot app icon and logo.

## The mark

The mark is four voice bars, then an amber text cursor.

- The voice bars: earshot listens when you hold the key.
- The cursor: earshot puts the cursor in the message box. It never sends.

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
| `logo.svg`, `logo.png` | Tile and wordmark, for a light background. |
| `logo-dark.svg`, `logo-dark.png` | Tile and wordmark, for a dark background. |
| `preview.png` | Review sheet with all sizes. |
| `src/mark.svg` | Source of the mark (1024 canvas, tile at 100,100, 824 wide). It uses the gradients that `render.py` defines. |
| `src/wordmark.svg` | "earshot" as outlines. |

## Colors

| Name | Value |
|---|---|
| Tile top | `#3A2FA8` |
| Tile bottom | `#0E0B2E` |
| Voice bars | `#FFFFFF` to `#C4BAFF` |
| Cursor | `#FFD978` to `#FF9A3C` |
| Ink (wordmark on light) | `#14112E` |

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
