# Mixed-content control render
Digits and Latin inside Arabic text. `result.png` is the engine's output.
Row A `330 إلى 400 سعرة` inline → digits backwards. Row G `تحتاج 330 سعرة` → backwards AND words inverted.
**Row F** `تحتاج <span>330</span> سعرة` → correct. Row B `330-400` alone → correct.
→ Wrap every non-Arabic run in its own nested span, spaces outside. `helpers/rtl-spans.mjs` `staticLine()`. See `references/arabic-captions.md` §2.
