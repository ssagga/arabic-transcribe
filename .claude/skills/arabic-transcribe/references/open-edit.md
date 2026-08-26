# Using this with open-edit

[open-edit](https://github.com/veedstudio/open-edit) renders captioned video. Its
transcription seam is a single file — `runs/<key>/transcript.json` — and it ships a
`custom` provider for exactly this case: bring your own transcriber, hand it a
Whisper-family JSON, and nothing downstream can tell which one ran.

## The one command

```bash
bash ~/.agents/skills/arabic-transcribe/scripts/openedit.sh video.mp4
```

Finds the open-edit runtime, transcribes, maps the result in, and runs prep. Then
it prints the next commands in the normal flow.

Pass `--root` if the runtime is somewhere unusual:

```bash
bash .../openedit.sh video.mp4 --root ~/myproject/.open-edit/runtime
```

## The same thing by hand

```bash
python3 ~/.agents/skills/arabic-transcribe/scripts/transcribe_ar.py video.mp4 -o ar.json

cd "$OPEN_EDIT_ROOT"
node --import tsx prep/whisper.ts ar.json /abs/path/video.mp4   # -> runs/<key>/transcript.json
node --import tsx prep/prep.ts /abs/path/video.mp4              # -> meta + word timings + frames
```

`<key>` is the video's filename without its extension, whitespace replaced by `_`.

Then continue the normal open-edit flow — style, design + render, mux.

## Do not rewrite the recorded provider

It is tempting to run:

```bash
node --import tsx prep/transcribe.ts --record custom     # ← usually wrong
```

That preference is **global**. Setting it to `custom` routes every future clip
through here, including English ones, where WhisperX or VEED is the better tool.
Drive this route per-clip instead, and only record `custom` if the person works
almost entirely in Arabic.

## Telling an agent to use this

Anything an agent reads at session start works — a `CLAUDE.md`, an `AGENTS.md`, or
just saying it once in chat:

```markdown
For Arabic video, use the `arabic-transcribe` skill instead of the default
transcription provider: run `scripts/openedit.sh <video>`, then continue the
normal open-edit flow. Read `references/arabic-captions.md` before designing
captions — Arabic needs an Arabic typeface and reversed per-word span order.
```

## The captions are the hard part, not the transcript

The stock recipes are built for Latin type and will produce a broken Arabic video
even with a perfect transcript:

- Their fonts carry **no Arabic glyphs**.
- Per-word spans render **in reverse** — every word correct, every sentence
  backwards. This survives every gate in the pipeline.

So an Arabic clip is a **creative run** (the authored path), not a stock recipe
run. Read `references/arabic-captions.md` first, and use `helpers/rtl-spans.mjs`
to emit the spans.

Nothing in this repo modifies open-edit. It writes one JSON file and calls two of
its scripts.
