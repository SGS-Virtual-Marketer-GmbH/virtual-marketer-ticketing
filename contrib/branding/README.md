# Branding generation

Zammad's logo lives in about a dozen places across three coexisting frontends,
plus a raster favicon/PWA set and a prebuilt SVG sprite. Hand-editing those does
not survive an upstream merge, and it is easy to miss one — an earlier hand pass
in this repo left Zammad's own logo in the `icons.svg` sprite (which is what the
*default* legacy UI actually renders) and put a squashed square bitmap into the
91x15 horizontal wordmark slot.

So every branding asset is generated from one vector source.

```sh
python3 contrib/branding/generate.py              # build + install into the tree
python3 contrib/branding/generate.py --build-only # build into contrib/branding/build only
```

Requires `python3` with `fonttools` and `Pillow`, and `node` with
`@resvg/resvg-js` (installed under `contrib/branding/node_modules`).

## Inputs

| Input | Purpose |
| --- | --- |
| `src/logo.svg` | The brand mark. True vector, ~23 flat-colour paths approximating a gradient. |
| `../../public/assets/fonts/Inter-SemiBold.ttf` | Wordmark typeface — the app's own UI font (see `font.css`), so the wordmark matches the interface. |

The wordmark is converted to **outlines**, not left as `<text>`, so it renders
identically regardless of the fonts installed on the viewer's machine.

## Generated assets

| Built file | Installed to |
| --- | --- |
| `mark-colour.svg` | `public/assets/images/logo.svg` (login page), `public/assets/images/icons/logo.svg`, `logo.svg` |
| `mark-flat.svg` | desktop + mobile `logo-flat.svg`, desktop `logo.svg`, `CommonUserAvatar/assets/logo.svg` |
| `wordmark.svg` | `public/assets/images/icons/logotype.svg` |
| `full-logo.svg` | `public/assets/images/icons/full-logo.svg` |
| (raster) | `public/favicon.ico`, `public/apple-touch-icon.png`, `public/assets/frontend/app-icon-{192,512}.png` |
| (sprite) | `icons.svg` symbols `icon-logo`, `icon-logotype`, `icon-full-logo` |

## Two variants, deliberately

- **Colour** — used where the background is known (login page, favicon, app
  icons).
- **Flat `currentColor`** — used everywhere the logo sits on themed chrome
  (sidebar, avatars, "Powered by" footers) so it stays legible in both light and
  dark themes. The source art's darkest tone is a deep crimson that would
  disappear against the dark sidebar.

Two details worth not re-litigating:

- The flat variant re-strokes each path in `currentColor` at width **1.5**. The
  source approximates a gradient with abutting flat-colour bands; without a
  stroke, hairline seams show through. At width 3.0 the M's counters fill in.
- `padded_viewbox()` grows the viewBox by 6%. The source art bleeds to all four
  edges, which looks cramped as a favicon and gets clipped by the circular mask
  iOS and Android apply to app icons.

## Not generated

`product_name` and the seeded trigger email footers are **database settings**,
seeded from `db/seeds/`. They apply on a fresh install and are editable in the
admin UI afterwards — they are not files this script owns.

Hardcoded strings patched by hand in the fork (re-check after an upstream merge):

- `app/models/channel/email_build.rb` — `X-Powered-By` / `X-Mailer` headers
- `app/controllers/mobile_controller.rb` — PWA manifest `short_name`
- `db/seeds/triggers.rb` — customer-facing auto-reply email footer
- `db/seeds/settings.rb` — `product_name` default
- the "Powered by" link targets in `*.jst.eco`, `LoginFooter.vue`,
  `LayoutPublicPage.vue`

Upstream copyright headers are deliberately left untouched — AGPL-3.0 §5
requires preserving them.
