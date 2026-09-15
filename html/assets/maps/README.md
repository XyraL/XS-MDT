# Map assets

| Path | What it is |
|---|---|
| `tiles/{z}_{x}_{y}.webp` | What the MDT actually loads — a Leaflet tile pyramid, 129 tiles across 5 zoom levels, flat in one directory so fxmanifest can glob them with a single `*`. Generated, not hand-edited. |
| `san-andreas-satellite.webp` | The 4096×6144 source render the tiles are cut from. Kept so the tiles can be rebuilt; **not** served to the NUI. |
| `OULSEN-LICENSE.txt` | MIT licence for the satellite render ([Oulsen/oulsen_satmap](https://github.com/Oulsen/oulsen_satmap)). |

## Rebuilding the tiles

After swapping the source image:

```bash
npm install sharp
node tools/build-map-tiles.js
```

If the new image has different dimensions, update `MAP.imageW` / `MAP.imageH` /
`MAP.nativeZoom` at the top of `html/js/panels/map.js` — the build script prints
the native zoom it used — and refit `MAP.world` unless the new render has the
same aspect ratio as the old one. The world rectangle's width:height has to
equal the image's, or one axis ends up scaled differently from the other.

## Calibrating the world bounds

`MAP.world` says which GTA world rectangle the render covers. The shipped
9000 x 13500 is 2:3, matching the 4096 x 6144 render, so the pixels stay square.

Do not nudge a single edge until a dot sits on you. That was the old advice here
and it is what put players up to 300m out — the bounds had been fitted against
landmarks that all sat on a north-south line, so nothing constrained X and the
rectangle ended up 9% too wide. It reads as a small offset on everyone rather
than a scale problem, because the error is near zero mid-map and only bites at
the edges.

To refit, keep the ratio locked to the image and use reference points near
opposite edges on both axes. The easiest ground truth is the render itself: it
is Oulsen's satmap, which has postal numbers drawn on it, and those are the
[dex_postal](https://github.com/DexterKray/dex_postal) set. Take a few postals
at the north tip, the south tip and both coasts and solve for the one rectangle
that puts all of them right.
