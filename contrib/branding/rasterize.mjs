// SVG -> PNG for the branding generator (see generate.py).
// Kept as a tiny separate script because Python has no dependency-free SVG
// renderer, while @resvg/resvg-js ships prebuilt native binaries.
//
//   node rasterize.mjs <in.svg> <out.png> <width> [background]

import { Resvg } from '@resvg/resvg-js';
import { readFileSync, writeFileSync } from 'node:fs';

const [, , src, out, width, background] = process.argv;

if (!src || !out || !width) {
  console.error('usage: rasterize.mjs <in.svg> <out.png> <width> [background]');
  process.exit(1);
}

// currentColor has no meaning outside a document context, so anything still
// carrying it would render transparent. Raster targets (favicon, app icons)
// are always built from the colour mark, but pin a sane value just in case.
const svg = readFileSync(src, 'utf8').replace(/currentColor/g, '#93112a');

const resvg = new Resvg(svg, {
  fitTo: { mode: 'width', value: Number(width) },
  background: background || 'rgba(0,0,0,0)',
});

writeFileSync(out, resvg.render().asPng());
