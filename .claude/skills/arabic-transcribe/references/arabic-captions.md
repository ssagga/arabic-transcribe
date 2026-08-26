# Captioning Arabic — read this before you design anything

Transcription is the easy half. Everything below was found by rendering, not by
reading a spec, and every one of them survives `lint`, `--verify`, the design gate
and `probe-qa` — because those check whether text is **drawn**, not whether it is
**readable**.

If you do not read Arabic, you cannot eyeball your way out of these. Use the
control render.

---

## 1. Word order inverts when you split a line per word

**The trap.** You split a caption into one span per word so the words can reveal
one at a time, put `direction: rtl` on the container, and every word renders
beautifully — connected, shaped, correct. And every sentence reads backwards.

The weave engine shapes the text inside each box correctly but lays inline-block
boxes out in **document order**. It does not reverse them for RTL. A browser does;
this engine does not.

**The fix.** Emit the spans **reversed**, keeping each word's reveal delay tied to
its *logical* reading position so the animation still runs in spoken order.

```js
import { rtlSpans } from '../helpers/rtl-spans.mjs';
html = rtlSpans('بل مع [[Time Stamps]]', { wordClass: 'cap', startSec: 46.54 });
```

**Verify, don't assume.** `examples/rtl-control-render` puts three variants of one
sentence side by side: a single span (the engine's own ordering — the reference),
per-word spans in logical order, and per-word spans reversed. Match against the
single span. If the logical-order row ever starts matching, the engine has gained
RTL box ordering and the reversal should be dropped.

A single span holding the whole line is always ordered correctly — so if you do not
need a per-word reveal, do not split the line at all.

## 2. Whitespace between spans collapses

Words render jammed together (`الكابشنزتكتبلسه`). The whitespace between
inline-block spans is dropped. Give each word an explicit margin:

```css
.cap { display: inline-block; margin-left: .28em; }
```

`rtlWordCss()` in the helper emits exactly this.

## 3. Latin display faces have no Arabic glyphs

Archivo, Inter, Archivo Narrow and most of the faces the stock recipes use carry no
Arabic at all. On Google Fonts, these do: **Cairo**, **Noto Kufi Arabic**,
**IBM Plex Sans Arabic**, **Tajawal**, **Almarai**.

Watch the render log. A warning naming *your* family
(`'Cairo' unresolved by Google — rendering with embedded variable fallback`) is
real and means the type identity is gone. Warnings naming generic keywords
(`'sans-serif'`, `'cursive'`) are harmless noise.

## 4. Keep Latin brand names as one token

`Cohere`, `WhisperX`, `Hugging Face`, `GitHub`, `keep building` — wrap each in
`[[double brackets]]` so the helper treats it as a single token. Reversing a
multi-word Latin phrase turns `keep building` into `building keep`.

Rendering tool names in Latin rather than Arabic transliteration is usually the
better call anyway: `WhisperX` reads as a product, `ويسبر اكس` reads as phonetics.

## 5. Animation delays on children are absolute

Not specific to Arabic, but it will bite you in the same document. `animation-delay`
on a child element is measured from the **document timeline**, never from when a
parent cue's animation starts. A cue-relative delay makes every line animate near
`t=0`, finish, and sit on its final keyframe long before its cue ever opens — so
captions late in the film simply never appear.

`probe-qa` catches this one, as `ink 0.00% — no visible caption`.

## 6. Give every line its own window

A line whose entrance uses `fill-mode: both` or `forwards` stays visible for the
rest of its cue. Several lines in one beat then pile up on top of each other. Give
each line a window that ends when the next one starts:

```css
@keyframes lw7 {
  0%      { opacity: 0; transform: translateY(16px) }
  18%     { opacity: 1; transform: none }   /* entrance, as a % of the window */
  99.99%  { opacity: 1; transform: none }
  100%    { opacity: 0 }
}
```

End the window a frame early — a gate closing exactly on a frame boundary loses
that frame, and `--verify` cannot see it.

## 7. Numerals are a choice

`٢٠٢٦` (Eastern Arabic) and `2026` (Western) are both correct in Saudi usage.
Western digits read as technical specs — good for `18GB`, `2B`, version numbers.
Eastern digits read as prose. Pick one rule per piece and hold it.

---

## Placement, for a talking head

Measure, don't guess. On a typical selfie-framed clip at 1080×1920 the head fills
roughly `y270–1260`, leaving under 50px of clear space above it — so captions
belong **below the chin**, over the chest, not above the head.

Bright rooms (white wall, white shirt, bright screens) defeat light type entirely.
A dark card with light type is the treatment that survives; make it a real device
used consistently, rather than a scrim dropped behind one hard-to-read line.
