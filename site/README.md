# earshot landing page

This folder holds the static landing page for earshot. The planned address is `https://earshot.divyekant.com`.

The page has no build step and no third-party requests. It uses the system font, so the browser loads no web fonts.

## Files

| File | Contents |
|---|---|
| `index.html` | The page. The text comes from the root `README.md`. |
| `style.css` | The styles. The colors come from `assets/brand/README.md`. |
| `demo.js` | The example commands in the hero window. If the reader asks for reduced motion, the first example stays still. |
| `assets/` | Copies of `logo-dark.svg`, `mark.svg` and `mark.png` from `assets/brand/`, and `og.png` (1200 × 630) for link previews. |

If the brand files in `assets/brand/` change, copy them into `site/assets/` again.

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
