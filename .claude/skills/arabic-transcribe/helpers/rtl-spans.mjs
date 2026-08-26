// Correct per-word spans for Arabic captions in the weave/open-edit engine.
//
// WHY THIS EXISTS
// ---------------
// Splitting a caption into one span per word is how you get a word-by-word reveal.
// In a browser, `direction: rtl` on the container then lays those spans out right to
// left and everything is fine. The weave engine does NOT do that: it shapes the text
// inside each box correctly but lays inline-block boxes out in DOCUMENT order.
//
// The result is the worst kind of bug — every word is beautifully rendered and every
// sentence reads backwards. It survives lint, --verify, the design gate and probe-qa,
// because all of those check whether text is DRAWN, not whether it is READABLE.
//
// Verified by control render (see examples/rtl-control-render): a single span holding
// the whole sentence orders natively and is the reference; per-word spans in logical
// order come out inverted against it; per-word spans in REVERSED order match it.
//
// Two more things this handles, both learned the same way:
//   * whitespace between inline-block spans COLLAPSES — words need an explicit margin
//     or they render as one long ligatureless run.
//   * animation-delay on a child is ABSOLUTE to the document timeline, never relative
//     to a parent cue's animation. Pass absolute seconds.

/** A [[bracketed]] run stays ONE token, so a Latin phrase is never reversed internally. */
export function tokenize(text) {
  const out = [];
  for (const part of String(text).split(/(\[\[[^\]]+\]\])/g).filter(Boolean)) {
    const m = part.match(/^\[\[(.+)\]\]$/);
    if (m) out.push({ latin: true, text: m[1] });
    else for (const w of part.trim().split(/\s+/).filter(Boolean)) out.push({ latin: false, text: w });
  }
  return out;
}

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

/**
 * Emit per-word spans for one right-to-left caption line.
 *
 * @param {string} text            e.g. "بل مع [[Time Stamps]]"
 * @param {object} opts
 * @param {string} opts.wordClass  class for Arabic word spans
 * @param {string} [opts.latinClass=opts.wordClass]  class for [[bracketed]] tokens
 * @param {number} opts.startSec   ABSOLUTE start time of the line, in seconds
 * @param {number} [opts.staggerMs=62]  gap between consecutive word reveals
 * @param {number} [opts.latinPx]  font-size override for latin tokens
 * @returns {string} HTML — spans in reversed document order, delays in reading order
 */
export function rtlSpans(text, opts) {
  const {
    wordClass, latinClass = opts.wordClass, startSec,
    staggerMs = 62, latinPx,
  } = opts;
  if (typeof startSec !== 'number' || !Number.isFinite(startSec)) {
    throw new Error('rtlSpans: startSec must be an absolute time in seconds');
  }
  return tokenize(text)
    // delay follows LOGICAL reading order, so the line still reveals as it is spoken
    .map((tok, i) => {
      const delay = (startSec + (i * staggerMs) / 1000).toFixed(3);
      const size = tok.latin && latinPx ? `;font-size:${latinPx}px` : '';
      const cls = tok.latin ? latinClass : wordClass;
      return `<span class="${cls}" style="animation-delay:${delay}s${size}">${esc(tok.text)}</span>`;
    })
    // ...but DOCUMENT order is reversed, because the engine will not reverse it for us
    .reverse()
    .join(' ');
}

/** The CSS a word span needs. `marginEm` is the fix for collapsed inter-word whitespace. */
export function rtlWordCss(cls, { marginEm = 0.28 } = {}) {
  return `.${cls}{display:inline-block;margin-left:${marginEm}em}`;
}

/** Google Fonts families that actually carry Arabic glyphs. Latin display faces do not. */
export const ARABIC_FACES = ['Cairo', 'Noto Kufi Arabic', 'IBM Plex Sans Arabic', 'Tajawal', 'Almarai'];
