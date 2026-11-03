# earshot landing page

This folder holds the static landing page for earshot. The planned address is `https://earshot.divyekant.com`.

The page has no build step and no third-party requests. The fonts are in `fonts/` on the same server.

## Files

| File | Contents |
|---|---|
| `index.html` | The page. The text comes from the root `README.md`. |
| `style.css` | The styles. Black ink on white, with soft grays. |
| `demo.js` | The film in the hero: spoken commands play out on a drawn Mac screen (chat, web, menus, numbers, dictation), and the timing chart. It is a simulation: no microphone and no network. It plays only while it is on screen. If the reader asks for reduced motion, each scene shows in its final state. |
| `fonts/` | Schibsted Grotesk (variable) and JetBrains Mono, as WOFF2 files, with their SIL Open Font License 1.1 texts. |
| `assets/` | Copies of `mark.svg` and `mark.png` from `assets/brand/` for the browser icon, and `og.png` (1200 × 630) for link previews. |

The page draws the one-color mark from `assets/brand/glyph.svg` inline. If the brand files change, update `site/` in the same pull request.

If the README text changes (commands, privacy, safety), update `index.html` in the same pull request.

## Preview

Open `site/index.html` in a browser. Or serve the folder:

```sh
python3 -m http.server 8080 --directory site
```

## Deploy

The page is a folder of static files. Any static web server can serve it. For the Caddy server that serves the other `divyekant.com` sites, use a block like this one:

```
earshot.divyekant.com {
	root * /srv/earshot-site
	encode zstd gzip
	file_server
	header {
		Content-Security-Policy "default-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
		Referrer-Policy "no-referrer"
		X-Content-Type-Options "nosniff"
	}
}
```

To publish a new version:

1. Add a DNS `A` record for `earshot` that points to the server.
2. Copy the contents of `site/` to `/srv/earshot-site` on the server.
3. Reload Caddy. Caddy gets the TLS certificate.
