# RTL control render

Proves how the engine orders per-word spans, instead of trusting the CSS spec.

```bash
"$OPEN_EDIT_ROOT/.veed-engine/veed-engine-cli" . --record out.mp4
ffmpeg -ss 0.5 -i out.mp4 -frames:v 1 out.png
```

Three rows of the same sentence — `واحد اثنان ثلاثة` ("one two three"):

| Row | Construction | Result |
|-----|--------------|--------|
| A | one span, whole sentence | **the reference** — the engine orders this natively |
| B | per-word spans, logical order, `direction: rtl` | inverted against A |
| C | per-word spans, **reversed** order | matches A |

If B still disagrees with A on your engine build, keep reversing (use
`helpers/rtl-spans.mjs`). If B ever starts matching A, the engine has learned to
reorder inline-block boxes for RTL and the reversal should be dropped.

Read A as the truth: `واحد` must sit on the RIGHT.
