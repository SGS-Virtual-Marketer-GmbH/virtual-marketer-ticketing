#!/usr/bin/env python3
"""
Regenerate every Virtual Marketer branding asset from a single vector source.

Why this exists
---------------
Zammad's logos live in ~10 places across three frontends (legacy CoffeeScript,
Vue mobile, Vue desktop) plus a raster favicon/PWA icon set. Hand-editing them
does not survive an upstream merge, and an earlier hand pass in this repo left
the *wordmark* (a 91x15 horizontal text logo) holding a squashed square bitmap.

So branding is generated, never hand-edited. After merging upstream Zammad,
re-run this script and the branding is reapplied deterministically.

    python3 contrib/branding/generate.py

Inputs  : contrib/branding/src/logo.svg  (true vector, multi-path, 512x512)
          public/assets/fonts/FiraSans-Medium.ttf  (Zammad's own UI typeface)
Outputs : see TARGETS at the bottom of this file.

Rasterisation is delegated to contrib/branding/rasterize.mjs (@resvg/resvg-js),
because Python has no dependency-free SVG renderer.
"""

import re
import subprocess
import sys
from pathlib import Path

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[2]
SRC = Path(__file__).resolve().parent / "src"
BUILD = Path(__file__).resolve().parent / "build"

LOGO_SRC = SRC / "logo.svg"
FONT = ROOT / "public" / "assets" / "fonts" / "FiraSans-Medium.ttf"

WORDMARK_TEXT = "Virtual Marketer"
TITLE = "Virtual Marketer Ticketing logo"

# Seam-closing stroke. The source art approximates a gradient with ~12 abutting
# flat-colour paths; dropping their strokes reveals hairline gaps between bands.
# 1.5 closes them without thickening the M's counters (3.0 visibly filled them).
SEAM_STROKE = "1.5"


# --------------------------------------------------------------------------
# source parsing
# --------------------------------------------------------------------------

def load_source():
    """Return (inner_svg_markup, viewbox) for the brand mark."""
    svg = LOGO_SRC.read_text()
    vb = re.search(r'viewBox="([^"]+)"', svg).group(1)
    inner = svg[svg.index(">", svg.index("<svg")) + 1: svg.rindex("</svg>")]
    return inner, vb


def strip_stroke_overlay(inner):
    """Drop the stroke-only <g> that only exists to hide anti-alias seams."""
    return re.sub(r"<g stroke-width.*?</g>", "", inner, flags=re.S)


def to_flat(inner):
    """Recolour every filled path to currentColor for theme-adaptive icons."""
    out = strip_stroke_overlay(inner)
    out = re.sub(r'fill="(?!none)[^"]*"', "fill=\"currentColor\"", out)
    out = re.sub(r'\s*stroke="[^"]*"', "", out)
    out = re.sub(r'\s*vector-effect="[^"]*"', "", out)
    return out.replace(
        'fill="currentColor"',
        f'fill="currentColor" stroke="currentColor" stroke-width="{SEAM_STROKE}"'
        ' stroke-linejoin="round"',
    )


# --------------------------------------------------------------------------
# wordmark: text -> vector paths (no <text>, so it renders identically anywhere)
# --------------------------------------------------------------------------

def wordmark_paths(text, cap_height_px):
    """Convert `text` to SVG path data using Zammad's own Fira Sans."""
    font = TTFont(FONT)
    upem = font["head"].unitsPerEm
    cmap = font.getBestCmap()
    glyphset = font.getGlyphSet()
    hmtx = font["hmtx"]

    kern = {}
    if "kern" in font:
        for table in font["kern"].kernTables:
            kern.update(table.kernTable)

    parts, x = [], 0
    prev = None
    for ch in text:
        name = cmap.get(ord(ch))
        if name is None:
            continue
        if prev is not None:
            x += kern.get((prev, name), 0)
        pen = SVGPathPen(glyphset)
        glyphset[name].draw(pen)
        d = pen.getCommands()
        if d:  # space has no outline
            parts.append(f'<path d="{d}" transform="translate({x} 0)"/>')
        x += hmtx[name][0]
        prev = name

    # Font units are y-up; SVG is y-down. Flip, then scale cap height to target.
    scale = cap_height_px / font["OS/2"].sCapHeight
    width = x * scale
    return (
        f'<g transform="scale({scale} {-scale}) translate(0 {-font["OS/2"].sCapHeight})"'
        f' fill="currentColor">{"".join(parts)}</g>',
        width,
    )


# --------------------------------------------------------------------------
# svg assembly
# --------------------------------------------------------------------------

def svg_doc(width, height, viewbox, body, title=TITLE):
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="no"?>\n'
        f'<svg width="{width}" height="{height}" viewBox="{viewbox}" version="1.1"'
        ' xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">\n'
        f"<title>{title}</title>\n{body}\n</svg>\n"
    )


def padded_viewbox(vb, pad_ratio):
    """Grow a viewBox outward so the mark is not flush against the edges.

    The source art bleeds to all four edges, which looks cramped as a favicon
    and gets clipped by the circular mask iOS/Android apply to app icons.
    """
    x, y, w, h = (float(v) for v in vb.replace(",", " ").split())
    px, py = w * pad_ratio, h * pad_ratio
    return f"{x - px} {y - py} {w + 2 * px} {h + 2 * py}"


def build():
    inner, vb = load_source()
    colour_inner = strip_stroke_overlay(inner)
    flat_inner = to_flat(inner)
    padded = padded_viewbox(vb, 0.06)

    BUILD.mkdir(exist_ok=True)
    out = {}

    # 1. Colour mark, square, padded — login page + favicon/app-icon source.
    out["mark-colour.svg"] = svg_doc(512, 512, padded, colour_inner)

    # 2. Flat mono mark — sidebar / avatar CommonIcon, inherits theme colour.
    out["mark-flat.svg"] = svg_doc(42, 38, padded, flat_inner)

    # 3. Wordmark — replaces Zammad's 91x15 "Zammad" logotype.
    # wordmark_paths() already lands the cap top on y=0 and the baseline on
    # y=cap, so no further vertical translate is needed here; adding one is
    # what pushed the baseline outside the viewBox on the first attempt.
    cap = 11.0
    wm, wm_w = wordmark_paths(WORDMARK_TEXT, cap)
    out["wordmark.svg"] = svg_doc(round(wm_w), 15, f"0 -1 {wm_w} 15", wm)

    # 4. Full logo — mark + wordmark on one baseline (Zammad ships 175x50).
    mh = 50.0
    mx0, my0, mw, mh0 = (float(v) for v in padded.split())
    mark_scale = mh / mh0
    mark_w = mw * mark_scale
    gap = 10.0
    wm_cap = 16.0
    wm_full, wm_full_w = wordmark_paths(WORDMARK_TEXT, wm_cap)
    total = mark_w + gap + wm_full_w
    out["full-logo.svg"] = svg_doc(
        round(total), 50, f"0 0 {total} 50",
        f'<g transform="scale({mark_scale}) translate({-mx0} {-my0})">{flat_inner}</g>'
        # Centre the cap-height band in the 50px canvas: cap top at (h-cap)/2.
        f'<g transform="translate({mark_w + gap} {(mh - wm_cap) / 2})">{wm_full}</g>',
    )

    # 5. Login lockup — colour mark + dark wordmark, side by side.
    #
    # The login page is the one place the brand has to introduce itself, so it
    # gets the full lockup rather than the bare mark. Distinct from full-logo:
    # that one is flat currentColor for themed chrome, this keeps the mark in
    # colour because it sits on a known white card.
    lock_h = 64.0
    mark_scale = lock_h / mh0
    mark_w = mw * mark_scale
    gap = 18.0
    wm_cap = 22.0
    wm_lock, wm_lock_w = wordmark_paths(WORDMARK_TEXT, wm_cap)
    total = mark_w + gap + wm_lock_w
    out["lockup.svg"] = svg_doc(
        round(total), round(lock_h), f"0 0 {total} {lock_h}",
        f'<g transform="scale({mark_scale}) translate({-mx0} {-my0})">{colour_inner}</g>'
        f'<g transform="translate({mark_w + gap} {(lock_h - wm_cap) / 2})"'
        f' style="color:#2d3748">{wm_lock}</g>',
    )

    for name, content in out.items():
        (BUILD / name).write_text(content)
        print(f"  built {name} ({len(content)} bytes)")
    return out


# Where each generated asset gets installed. One source -> many Zammad slots.
TARGETS = {
    "mark-colour.svg": [
        "public/assets/images/icons/logo.svg",
        "logo.svg",                                 # repo root
    ],
    # product_logo's disk fallback — this is what the LOGIN page renders, so
    # it gets the full lockup (mark + wordmark), not the bare mark.
    "lockup.svg": ["public/assets/images/logo.svg"],
    "mark-flat.svg": [
        "app/frontend/apps/desktop/initializer/assets/logo.svg",
        "app/frontend/apps/desktop/initializer/assets/logo-flat.svg",
        "app/frontend/apps/mobile/initializer/assets/logo-flat.svg",
        "app/frontend/shared/components/CommonUserAvatar/assets/logo.svg",
    ],
    "wordmark.svg": ["public/assets/images/icons/logotype.svg"],
    "full-logo.svg": ["public/assets/images/icons/full-logo.svg"],
}

# Raster targets: (source svg, dest, width, background)
RASTER = [
    ("mark-colour.svg", "public/apple-touch-icon.png", 180, "white"),
    ("mark-colour.svg", "public/assets/frontend/app-icon-192.png", 192, "white"),
    ("mark-colour.svg", "public/assets/frontend/app-icon-512.png", 512, "white"),
]


def patch_sprite():
    """Swap the logo symbols inside the prebuilt icons.svg sprite.

    The legacy CoffeeScript UI — still Zammad's *default* frontend — renders
    its header logo via `@Icon('logo')`, which resolves against this sprite,
    not against the standalone icon files. Upstream builds the sprite with
    gulp from icons/*.svg, but that toolchain pins gulp-util, which is
    abandoned and does not install on current Node. Patching the three logo
    symbols in place is equivalent for our purposes and keeps this script
    dependency-free.

    All three use the flat currentColor art so they stay legible against both
    the dark sidebar and light backgrounds; the colour mark is reserved for
    the login page and raster icons, where the background is known.
    """
    sprite = ROOT / "public" / "assets" / "images" / "icons.svg"
    if not sprite.exists():
        print("  ! skip icons.svg (missing)")
        return

    def inner_and_viewbox(name):
        svg = (BUILD / name).read_text()
        vb = re.search(r'viewBox="([^"]+)"', svg).group(1)
        body = svg[svg.index(">", svg.index("<svg")) + 1: svg.rindex("</svg>")]
        body = re.sub(r"<title>.*?</title>", "", body, flags=re.S)
        return body.strip(), vb

    text = sprite.read_text()
    for symbol_id, source in (
        ("icon-logo", "mark-flat.svg"),
        ("icon-logotype", "wordmark.svg"),
        ("icon-full-logo", "full-logo.svg"),
    ):
        body, vb = inner_and_viewbox(source)
        replacement = (
            f'<symbol id="{symbol_id}" viewBox="{vb}">\n'
            f"    <title>{symbol_id.removeprefix('icon-')}</title>\n"
            f"    {body}\n</symbol>"
        )
        text, n = re.subn(
            rf'<symbol id="{symbol_id}".*?</symbol>',
            lambda _m, r=replacement: r,
            text,
            count=1,
            flags=re.S,
        )
        print(f"  -> icons.svg#{symbol_id}" if n else f"  ! {symbol_id} not found")
    sprite.write_text(text)


def install():
    for name, dests in TARGETS.items():
        for dest in dests:
            p = ROOT / dest
            if not p.parent.exists():
                print(f"  ! skip {dest} (missing dir)")
                continue
            p.write_text((BUILD / name).read_text())
            print(f"  -> {dest}")

    for src, dest, width, bg in RASTER:
        p = ROOT / dest
        if not p.parent.exists():
            print(f"  ! skip {dest} (missing dir)")
            continue
        subprocess.run(
            ["node", str(Path(__file__).parent / "rasterize.mjs"),
             str(BUILD / src), str(p), str(width), bg],
            check=True,
        )
        print(f"  -> {dest} ({width}px)")

    # favicon.ico needs several sizes in one container; PIL writes them all.
    from PIL import Image
    png = BUILD / "favicon-256.png"
    subprocess.run(
        ["node", str(Path(__file__).parent / "rasterize.mjs"),
         str(BUILD / "mark-colour.svg"), str(png), "256", "white"],
        check=True,
    )
    Image.open(png).save(
        ROOT / "public" / "favicon.ico",
        sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )
    print("  -> public/favicon.ico (16-256px)")

    patch_sprite()


if __name__ == "__main__":
    if not LOGO_SRC.exists():
        sys.exit(f"missing brand source: {LOGO_SRC}")
    print("building branding assets...")
    build()
    if "--build-only" not in sys.argv:
        print("installing into tree...")
        install()
    print("done.")
