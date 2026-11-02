# earshot brand assets

This folder holds the earshot app icon and logo.

## The mark

The mark is an ear with a text cursor in the ear canal. Two arcs show the sound that comes in.

- The ear: earshot listens when you hold the key.
- The cursor: earshot puts the cursor in the message box. It never sends.

## Files

| File | Use |
|---|---|
| `AppIcon.icns` | App bundle icon. Copy to `Contents/Resources/AppIcon.icns` and set `CFBundleIconFile` to `AppIcon`. |
| `AppIcon.appiconset/` | Xcode asset catalog icon set (all macOS sizes and `Contents.json`). |
| `AppIcon.iconset/` | Input for `iconutil -c icns AppIcon.iconset`, if you want to rebuild the `.icns` with Apple tools. |
| `AppIcon.svg` | Icon master, 1024 × 1024. |
| `mark.svg`, `mark.png` | The tile with the mark, no shadow, 512 × 512. |
| `logo.svg`, `logo.png` | Tile and wordmark, for a light background. |
| `logo-dark.svg`, `logo-dark.png` | Tile and wordmark, for a dark background. |
| `preview.png` | Review sheet with all sizes. |
| `src/mark.svg` | Source of the mark (1024 canvas, tile at 100,100, 824 wide). |
| `src/wordmark.svg` | "earshot" as outlines. |

## Colors

| Name | Value |
|---|---|
| Tile top | `#6A5CFF` |
| Tile bottom | `#24166B` |
| Cursor | `#FFC24B` |
| Ink (wordmark on light) | `#1B1340` |

## Rebuild

Edit `src/mark.svg`, then run:

```sh
cd assets/brand
uv run render.py
```

The script needs no Apple tools. It writes the `.icns` file directly.

To rebuild the wordmark from a font file:

```sh
uv run render.py --wordmark /path/to/InterDisplay-SemiBold.otf
```

## Font

The wordmark uses Inter Display SemiBold, as outlines. Inter is under the SIL Open Font License 1.1. The SVG and PNG files do not need the font.
