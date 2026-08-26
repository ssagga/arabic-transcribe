# arabic-transcribe

**Accurate Arabic transcription with word-level timings — for AI agents that edit video.**

Whisper is the default transcriber in most agent video pipelines, and it is bad at
dialectal Arabic. This gives your agent a transcriber that isn't, plus the hard-won
knowledge it needs to actually put Arabic text on screen without embarrassing you.

Runs entirely on your machine. No API keys, no per-minute cost, no audio leaving the
laptop.

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/ssagga/arabic-transcribe/main/install.sh | bash
```

That installs the skill for every agent on your machine (Claude Code, Codex, Cursor,
Windsurf), builds the two Python environments, and tells you what's left to do.

<details>
<summary>Prefer a clone, or <code>npx skills add</code>?</summary>

```bash
git clone https://github.com/ssagga/arabic-transcribe.git
cd arabic-transcribe && ./install.sh
```

or, if you use the skills CLI (needs Node ≥ 20.12 — it crashes silently below that):

```bash
npx skills add ssagga/arabic-transcribe
bash ~/.agents/skills/arabic-transcribe/scripts/setup.sh
```
</details>

### One thing only you can do

The model is gated. Two steps, both yours — an agent shouldn't do them for you, and
should never ask for your token in chat:

1. **Accept the terms** (instant, auto-approved) at
   [the model page](https://huggingface.co/CohereLabs/cohere-transcribe-arabic-07-2026)
2. **Log in on this machine:**
   ```bash
   ~/.local/share/arabic-asr/asr-venv/bin/hf auth login
   ```

Accepting on the website grants your *account* access. This *machine* still needs a
token — that trips almost everyone up once.

### Check it

```bash
bash ~/.agents/skills/arabic-transcribe/scripts/doctor.sh
```

Verifies ffmpeg, both environments, TLS certificates, model access, GPU
acceleration and free disk — and names the fix for anything missing. Pass a media
file to run a real end-to-end test.

**Costs:** ~10 GB of disk (4 GB environments, 4.13 GB model weights, 1.2 GB aligner).
Roughly 7× realtime on Apple Silicon — a 60-second clip takes about 30 seconds.

---

## Use it

```bash
# transcript with per-word timings
python3 ~/.agents/skills/arabic-transcribe/scripts/transcribe_ar.py clip.mp4 -o out.json

# or straight into an open-edit run
bash ~/.agents/skills/arabic-transcribe/scripts/openedit.sh clip.mp4
```

Output is WhisperX-shaped JSON — the Whisper-family format most tooling already reads:

```json
{
  "language": "ar",
  "segments": [
    { "start": 0.04, "end": 24.9, "text": "…",
      "words": [ { "word": "بدق", "start": 0.04, "end": 0.28, "score": 0.91 } ] }
  ]
}
```

## Tell your agent about it

Drop this into your project's `CLAUDE.md` / `AGENTS.md`, or just say it once in chat:

```markdown
For Arabic video, use the `arabic-transcribe` skill rather than the default
transcription provider: run `scripts/openedit.sh <video>`, then continue the normal
open-edit flow. Read `references/arabic-captions.md` before designing captions —
Arabic needs an Arabic typeface and reversed per-word span order.
```

Agents that read `SKILL.md` files find it on their own once installed.

---

## Why it exists

Measured on a 57-second Saudi-dialect clip, against WhisperX `medium`:

| | this | WhisperX medium |
|---|---|---|
| Words returned | 159 | 138 — **~13% of speech missing** |
| A whole spoken line | kept | silently absent |
| الجوائز *(prizes)* | correct | **الجواز** *(passport)* — 4× |
| Proper nouns (عيسى) | correct | mangled to يس |
| Code-switching (بوكسات وسناكان) | correct | partly mangled |
| Punctuation, hamza | present | absent |

`الجوائز` → `الجواز` is the shape of the problem. Not a typo — a change of meaning,
repeated four times, and headed straight onto the screen if you caption it.

## How it works

The Cohere model is excellent at Arabic and **returns no timestamps at all** — its
model card lists that under limitations. Captions need per-word times. So:

```
audio ──▶ split on quiet points ──▶ Cohere Transcribe Arabic ──▶ text
                                                                  │
              WhisperX forced alignment (Arabic wav2vec2) ◀────────┘
                                    │
                                    ▼
                     Whisper-family JSON, per-word timings
```

**Two virtualenvs, deliberately.** The model needs transformers ≥ 5.4; WhisperX pins
4.x and breaks on 5.x. They cannot share, so they exchange JSON on disk. Merging them
is the first "improvement" someone will try; it doesn't work.

**Quiet-point chunking.** The model's own extractor splits at a fixed 30 seconds and
cuts whichever word straddles the boundary — on the test clip that produced a garbled
`فزتي في صدق سنوي` at the seam. This searches ±3s around each boundary for the
lowest-energy moment instead.

**Alignment accuracy:** 100% of words timed, in order, cross-checked against
WhisperX's independently-derived timings on shared anchor words — **median difference
11 milliseconds**.

---

## ⚠ Putting Arabic on screen

A correct transcript is the easy half. Read
[`references/arabic-captions.md`](.claude/skills/arabic-transcribe/references/arabic-captions.md)
before you design captions.

The one that will get you:

> If a caption is split into one span per word for a reveal animation,
> `direction: rtl` is **not enough** in VEED's weave engine. It shapes each word
> correctly but lays inline-block boxes out in **document order**. Every word renders
> beautifully and **every sentence reads backwards.**

It passes lint, `--verify`, the design gate and `probe-qa` — every one of them checks
whether text is *drawn*, not whether it is *readable*. If you don't read Arabic you
will ship it.

The fix is in [`helpers/rtl-spans.mjs`](.claude/skills/arabic-transcribe/helpers/rtl-spans.mjs):
emit the spans reversed, keep each word's reveal delay in logical reading order.
Verify on your own engine build with
[`examples/rtl-control-render`](examples/rtl-control-render) — three variants of one
sentence, so you can see which construction the engine orders correctly instead of
trusting the spec.

Also in there: Latin display faces carry no Arabic glyphs, whitespace between
inline-block spans collapses, and child `animation-delay` is absolute to the document
timeline rather than relative to a parent cue.

---

## What's in the box

| Path | |
|---|---|
| `scripts/transcribe_ar.py` | the pipeline |
| `scripts/openedit.sh` | Arabic video → prepped open-edit run, one command |
| `scripts/setup.sh` | idempotent environment bootstrap |
| `scripts/doctor.sh` | diagnose the install and every known trap |
| `helpers/rtl-spans.mjs` | correct RTL per-word spans |
| `references/arabic-captions.md` | rendering Arabic — read before designing |
| `references/open-edit.md` | pipeline integration |
| `references/troubleshooting.md` | every failure mode seen so far |
| `examples/rtl-control-render/` | proves how your engine orders RTL spans |

Everything lives under `.claude/skills/arabic-transcribe/` so the skills CLI finds it.

## Uninstall

```bash
rm -rf ~/.local/share/arabic-asr ~/.agents/skills/arabic-transcribe
rm -f  ~/.claude/skills/arabic-transcribe ~/.codex/skills/arabic-transcribe \
       ~/.cursor/skills-cursor/arabic-transcribe
rm -rf ~/.cache/huggingface/hub/models--CohereLabs--cohere-transcribe-arabic-07-2026
# WhisperX is shared with other work — remove only if nothing else needs it:
# uv tool uninstall whisperx
```

## Credits & licence

Tooling here is MIT (see [LICENSE](LICENSE)).

It stands on work I did not write:
[Cohere Transcribe Arabic](https://huggingface.co/CohereLabs/cohere-transcribe-arabic-07-2026)
by Cohere Labs (Apache-2.0), [WhisperX](https://github.com/m-bain/whisperX) for
forced alignment, and
[jonatasgrosman/wav2vec2-large-xlsr-53-arabic](https://huggingface.co/jonatasgrosman/wav2vec2-large-xlsr-53-arabic)
as the Arabic aligner. Built to plug into
[open-edit](https://github.com/veedstudio/open-edit) by VEED.

Model licence terms are Cohere's and apply to your use of the weights.
