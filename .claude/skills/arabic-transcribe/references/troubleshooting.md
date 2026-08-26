# Troubleshooting

`doctor.sh` checks most of this for you. Run it first.

```bash
bash ~/.agents/skills/arabic-transcribe/scripts/doctor.sh
bash ~/.agents/skills/arabic-transcribe/scripts/doctor.sh clip.mp4   # + a real run
```

---

## `Not logged in`, or HTTP 401 on the model

The model is gated. Two steps, both yours — an agent cannot and should not do
either, and should never ask you for the token in chat:

1. Accept the terms (instant, auto-approved):
   <https://huggingface.co/CohereLabs/cohere-transcribe-arabic-07-2026>
2. `~/.local/share/arabic-asr/asr-venv/bin/hf auth login`

Accepting the terms on the website is **necessary but not sufficient** — that
grants your account access; this machine still needs a token.

## `CERTIFICATE_VERIFY_FAILED` while downloading the aligner

macOS python.org builds ship without a CA store. The transcriber points TLS at the
virtualenv's `certifi` bundle itself, so this should not surface. If it does
somewhere else:

```bash
export SSL_CERT_FILE="$(ls ~/.local/share/arabic-asr/asr-venv/lib/python*/site-packages/certifi/cacert.pem)"
export REQUESTS_CA_BUNDLE="$SSL_CERT_FILE"
```

The permanent fix is running `Install Certificates.command` from your
`/Applications/Python 3.x/` folder.

## A wall of `libtorchcodec` / `dlopen` / `Library not loaded` errors

Harmless. WhisperX (via pyannote) probes for FFmpeg builds it cannot find and
prints a frightening amount of output. The signal that alignment worked is the
`[align] … words, … timed` line. If that line is absent, read the **last** error,
not the dlopen wall.

## `CohereAsrForConditionalGeneration` cannot be imported

The ASR environment is on transformers < 5.4. Rebuild it:

```bash
rm -rf ~/.local/share/arabic-asr/asr-venv
bash ~/.agents/skills/arabic-transcribe/scripts/setup.sh
```

Do **not** upgrade the WhisperX environment to transformers 5.x to "unify" them —
WhisperX pins 4.x and breaks. The two environments are separate on purpose and
exchange JSON on disk.

## `ffmpeg: no decoder found for apple_apac`

iPhone clips recorded with spatial audio carry a second, undecodable audio track.
Map only the streams you want:

```bash
ffmpeg -i in.MOV -map 0:v:0 -map 0:a:0 -c:v libx264 -c:a aac out.mp4
```

`ffprobe -show_entries stream=index,codec_type,codec_name` will show you the extra
track.

## `Operation not permitted` reading a file

macOS TCC protects `~/Downloads`, `~/Desktop` and `~/Documents`. A terminal or
agent without Full Disk Access can list those folders but not read the files. Move
the media into your project folder, or grant access in
System Settings → Privacy & Security → Full Disk Access.

## `npx skills add` crashes on `styleText`

The `skills` CLI needs Node ≥ 20.12 (it imports `styleText` from `node:util`).
Older Node dies at import with a `SyntaxError` before doing anything, which looks
like the install silently doing nothing.

```bash
node -v          # need >= 20.12
brew install node
```

This pipeline itself is pure Python and does not care about your Node version. The
open-edit runtime does.

## Words come back with no timing

Reported on the `[align]` line. The text is complete; downstream interpolates those
windows from timed neighbours. A handful is normal. All of them means the aligner
failed — check the language code and that the audio actually contains speech.

## A garbled phrase at a chunk seam

Chunking splits on the quietest point near each boundary rather than on a fixed
clock, precisely to avoid cutting a word in half. If you still see a mangled phrase
where two chunks meet, shorten `--chunk-sec` so boundaries land elsewhere:

```bash
transcribe_ar.py clip.mp4 --chunk-sec 18
```

## The model transcribes silence or music

It is eager, per its own model card — an encoder-decoder ASR will emit text for
non-speech. Trim leading/trailing music, or ignore the spurious segments.

## Slow

`doctor.sh` prints which accelerator torch found. On Apple Silicon expect MPS and
roughly 7× realtime. CPU-only is roughly realtime — slow, not broken.
