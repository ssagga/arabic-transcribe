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

## 2. Multi-digit Eastern Arabic numerals render backwards

`١٠` renders as `٠١`. `١٢٠` renders as `٠٢١`. The engine lays the digit run out right-to-left
along with the surrounding Arabic, where the bidi algorithm would normally isolate it.

**`direction: ltr` on the span does not fix it** — the engine ignores `direction` here exactly as
it ignores it for box order (§1).

Two options, control-rendered:

| Construction | Result |
|---|---|
| `١٠` plain in an rtl block | `٠١` — wrong |
| `١٠` in a `direction:ltr` span | `٠١` — still wrong |
| `٠١` pre-reversed in the source | `١٠` — correct, but fragile |
| `10` Western digits | `10` — **correct, no intervention** |

**Use Western digits.** They need no workaround, they survive the engine learning bidi, and they
are what Saudi and Gulf social content uses anyway. Pre-reversing works today and silently inverts
every number in your film the day this is fixed.

A single digit (`٥`, `٨`) has nothing to reorder and is safe either way — which is exactly why this
hides: it looks fine until a number reaches two digits.

**But Western digits are only safe when ALONE in an element.** A second control render
(`examples/mixed-content-control-render`) found that a number or a Latin word sitting *inline*
inside Arabic text — `تحتاج 330 سعرة` — renders the digits backwards *and* inverts the words
around it. The fix is to wrap every non-Arabic run in its own **nested `<span>`**, spaces kept
outside the span:

| Construction | Result |
|---|---|
| `تحتاج 330 سعرة` plain | `033`, words inverted — wrong |
| `تحتاج <span>330</span> سعرة` | correct digits, correct order |
| `330-400` alone in a block | correct |

In a per-word animated line each word is already its own span, so this is automatic. In a
static single-span line — a carousel slide, a title — you must isolate the run yourself.
`helpers/rtl-spans.mjs` exports `staticLine()` for exactly this.

## 3. Whitespace between spans collapses

Words render jammed together (`الكابشنزتكتبلسه`). The whitespace between
inline-block spans is dropped. Give each word an explicit margin:

```css
.cap { display: inline-block; margin-left: .28em; }
```

`rtlWordCss()` in the helper emits exactly this.

## 4. Latin display faces have no Arabic glyphs

Archivo, Inter, Archivo Narrow and most of the faces the stock recipes use carry no
Arabic at all. On Google Fonts, these do: **Cairo**, **Noto Kufi Arabic**,
**IBM Plex Sans Arabic**, **Tajawal**, **Almarai**.

Watch the render log. A warning naming *your* family
(`'Cairo' unresolved by Google — rendering with embedded variable fallback`) is
real and means the type identity is gone. Warnings naming generic keywords
(`'sans-serif'`, `'cursive'`) are harmless noise.

## 5. Keep Latin brand names as one token

`Cohere`, `WhisperX`, `Hugging Face`, `GitHub`, `keep building` — wrap each in
`[[double brackets]]` so the helper treats it as a single token. Reversing a
multi-word Latin phrase turns `keep building` into `building keep`.

Rendering tool names in Latin rather than Arabic transliteration is usually the
better call anyway: `WhisperX` reads as a product, `ويسبر اكس` reads as phonetics.

## 6. Animation delays on children are absolute

Not specific to Arabic, but it will bite you in the same document. `animation-delay`
on a child element is measured from the **document timeline**, never from when a
parent cue's animation starts. A cue-relative delay makes every line animate near
`t=0`, finish, and sit on its final keyframe long before its cue ever opens — so
captions late in the film simply never appear.

`probe-qa` catches this one, as `ink 0.00% — no visible caption`.

## 7. Give every line its own window

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

## 8. Numerals — which system

Both are correct in Saudi usage and it is a real design choice — Western digits read as
technical specs, Eastern digits read as prose. But see §2: **only Western digits actually render
correctly** in this engine beyond a single digit. Pick Western unless you have verified otherwise
on your build.

---

## Placement, for a talking head

Measure, don't guess. On a typical selfie-framed clip at 1080×1920 the head fills
roughly `y270–1260`, leaving under 50px of clear space above it — so captions
belong **below the chin**, over the chest, not above the head.

Bright rooms (white wall, white shirt, bright screens) defeat light type entirely.
A dark card with light type is the treatment that survives; make it a real device
used consistently, rather than a scrim dropped behind one hard-to-read line.
