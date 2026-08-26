---
name: arabic-transcribe
description: Transcribe Arabic audio or video with word-level timings, using Cohere Transcribe Arabic for the text and forced alignment for the timings. Handles Modern Standard Arabic, Saudi and other Gulf dialects, and Arabic-English code-switching far better than Whisper. Use whenever Arabic speech has to become text — subtitles, captions, transcripts, quotes, search — and especially when the speaker is dialectal or mixes in English. Also the transcription provider to use for any Arabic clip going through the open-edit video pipeline.
---

# arabic-transcribe

Arabic speech → text **with per-word start/end times**, in one command.

```bash
python3 ~/.agents/skills/arabic-transcribe/scripts/transcribe_ar.py <media> -o out.json
```

Any audio or video ffmpeg can read. Writes WhisperX-shaped JSON — the Whisper-family
format `prep/whisper.ts` and most other tooling already accept.

Straight into open-edit:

```bash
bash ~/.agents/skills/arabic-transcribe/scripts/openedit.sh <video>
```

Everything working?

```bash
bash ~/.agents/skills/arabic-transcribe/scripts/doctor.sh
```

## Why not Whisper

Whisper degrades badly on dialectal Arabic. Measured on a 57s Gulf-dialect clip
against WhisperX `medium`:

| | Cohere + alignment | WhisperX medium |
|---|---|---|
| Words returned | 159 | 138 (~13% of speech dropped) |
| A whole spoken line | kept | silently absent |
| الجوائز (prizes) | correct | **الجواز** (passport), 4× |
| Proper nouns (عيسى) | correct | mangled to يس |
| Code-switching (بوكسات وسناكان) | correct | partly mangled |
| Punctuation / hamza | present | absent |

`الجوائز` → `الجواز` is the shape of the problem: not a typo, a change of meaning,
repeated, and headed straight for the screen if it is captioned.

## How it works, and why it is two stages

**The model returns no timestamps at all** — its model card lists
"Timestamps/Speaker diarization" under limitations. So a second stage recovers them:

1. **Text** — `CohereLabs/cohere-transcribe-arabic-07-2026` (2B, Apache-2.0), in its
   own venv on transformers ≥ 5.4, GPU-accelerated via MPS or CUDA.
2. **Timings** — WhisperX forced alignment against
   `jonatasgrosman/wav2vec2-large-xlsr-53-arabic`, in the WhisperX venv on
   transformers 4.x.

The two need incompatible transformers majors, so they live in **separate
virtualenvs** and exchange JSON on disk. Do not merge them.

Measured: **100% of words timed**, in order, cross-checked against WhisperX's
independently-derived timings on shared anchor words — **median difference 11 ms**.
Fine for word-by-word caption reveals.

**Chunking is on quiet points, not a clock.** The model's own extractor splits at a
fixed 30s and cuts whichever word straddles the boundary — on the test clip that
produced a garbled `فزتي في صدق سنوي` at the seam. This searches ±3s around each
boundary for the lowest-energy moment. Do not replace it with a fixed split.

## Setup

```bash
bash ~/.agents/skills/arabic-transcribe/scripts/setup.sh --check   # report only
bash ~/.agents/skills/arabic-transcribe/scripts/setup.sh           # install what's missing
```

Idempotent. Installs ffmpeg, uv, both environments.

**The model is gated. Two steps belong to the user — never do them for them, and
never ask for the token in chat:**

1. Accept the terms (instant): <https://huggingface.co/CohereLabs/cohere-transcribe-arabic-07-2026>
2. `~/.local/share/arabic-asr/asr-venv/bin/hf auth login`

Accepting on the website grants the *account* access; the *machine* still needs a token.

Disk ~10 GB total. Speed ~7× realtime on Apple Silicon.

## Options

| Flag | Default | Notes |
|---|---|---|
| `-o, --out` | `<media>.ar.json` | output path |
| `--chunk-sec` | `25` | target chunk length; the cut lands on the nearest quiet point |
| `--language` | `ar` | passed to model and aligner |
| `--keep-wav` | off | keep the extracted 16 kHz mono wav |

## ⚠ Before you design Arabic captions

**Read `references/arabic-captions.md`.** A correct transcript is the easy half.

The one that will get you: if captions are split per word for a reveal animation,
`direction: rtl` is **not enough** in the weave engine. It shapes each word correctly
but lays inline-block boxes out in document order — so every word renders beautifully
and **every sentence reads backwards**. It passes lint, `--verify`, the design gate
and `probe-qa`, because all of those check whether text is drawn, not whether it is
readable.

Use `helpers/rtl-spans.mjs`, which emits the spans reversed while keeping each word's
reveal delay in logical reading order. Verify with `examples/rtl-control-render`.

Also: Latin display faces carry no Arabic glyphs (use Cairo, Noto Kufi Arabic, IBM
Plex Sans Arabic, Tajawal), and whitespace between inline-block spans collapses, so
word spans need an explicit margin.

## Files

| Path | What |
|---|---|
| `scripts/transcribe_ar.py` | the pipeline |
| `scripts/openedit.sh` | one command: Arabic video → prepped open-edit run |
| `scripts/setup.sh` | idempotent environment bootstrap |
| `scripts/doctor.sh` | diagnose the install and every known trap |
| `helpers/rtl-spans.mjs` | correct RTL per-word spans |
| `references/arabic-captions.md` | rendering Arabic — read before designing |
| `references/open-edit.md` | pipeline integration |
| `references/troubleshooting.md` | every failure mode seen so far |
