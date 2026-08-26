#!/usr/bin/env python3
"""
Arabic transcription with word-level timings.

Two stages, two virtualenvs (they need incompatible transformers majors):
  1. TEXT   Cohere Transcribe Arabic (transformers >= 5.4)  -> accurate MSA/dialect/code-switched text
  2. TIMES  wav2vec2 forced alignment via WhisperX (transformers 4.x) -> per-word start/end

Emits a WhisperX-shaped JSON, which is the Whisper-family format that
open-edit's `prep/whisper.ts` and most other tooling already accept.

The model itself returns NO timestamps of any kind (its model card lists that
as a limitation), which is why stage 2 exists and is not optional.

Usage (orchestrator - the normal way):
    python3 transcribe_ar.py <media> [-o out.json] [--chunk-sec 25] [--keep-wav]

Internal stage entry points (invoked by the orchestrator in the right venv):
    python3 transcribe_ar.py --stage asr   --wav a.wav --out text.json --chunk-sec 25
    python3 transcribe_ar.py --stage align --wav a.wav --text text.json --out final.json
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

MODEL_ID = "CohereLabs/cohere-transcribe-arabic-07-2026"
HOME = Path.home()
ASR_VENV = HOME / ".local/share/arabic-asr/asr-venv"
WHISPERX_TOOL = HOME / ".local/share/uv/tools/whisperx"

# ---------------------------------------------------------------- utilities


def die(msg, code=1):
    print(f"transcribe-ar: {msg}", file=sys.stderr)
    sys.exit(code)


def certifi_bundle(venv: Path):
    """macOS python.org builds ship no CA store; point TLS at the venv's certifi."""
    hits = list(venv.glob("lib/python*/site-packages/certifi/cacert.pem"))
    return str(hits[0]) if hits else None


def venv_env(venv: Path):
    env = os.environ.copy()
    bundle = certifi_bundle(venv)
    if bundle:
        env.setdefault("SSL_CERT_FILE", bundle)
        env.setdefault("REQUESTS_CA_BUNDLE", bundle)
    env.setdefault("TOKENIZERS_PARALLELISM", "false")
    return env


def extract_wav(media: Path, wav: Path):
    ff = shutil.which("ffmpeg") or die("ffmpeg not found (brew install ffmpeg)")
    subprocess.run(
        [ff, "-v", "error", "-i", str(media), "-vn", "-ac", "1", "-ar", "16000",
         "-c:a", "pcm_s16le", "-y", str(wav)],
        check=True,
    )


# ------------------------------------------------------- stage 1: the text


def quiet_split_points(audio, sr, chunk_sec, search_sec=3.0, win_ms=300):
    """
    Chunk boundaries placed at the QUIETEST point near each target time.

    The model's own feature extractor splits on a fixed 30s clock, which cuts
    whichever word happens to straddle it and garbles both sides. Measured on a
    real clip: a fixed split produced "فزتي في صدق سنوي" at the seam. Searching a
    window around the target for the lowest-energy moment costs nothing and
    removes the whole failure mode.
    """
    import numpy as np

    n = len(audio)
    total = n / sr
    if total <= chunk_sec:
        return [(0.0, total)]

    win = max(1, int(win_ms / 1000 * sr))
    # energy envelope, coarse hop for speed
    hop = max(1, win // 4)
    frames = np.lib.stride_tricks.sliding_window_view(np.abs(audio), win)[::hop]
    energy = frames.mean(axis=1)

    cuts = [0.0]
    t = chunk_sec
    while t < total - 1.0:
        lo = max(cuts[-1] + 2.0, t - search_sec)
        hi = min(total - 0.5, t + search_sec)
        if hi <= lo:
            cuts.append(min(t, total))
            t += chunk_sec
            continue
        i_lo, i_hi = int(lo * sr / hop), int(hi * sr / hop)
        i_hi = min(i_hi, len(energy) - 1)
        if i_hi <= i_lo:
            cut = t
        else:
            best = int(np.argmin(energy[i_lo:i_hi])) + i_lo
            cut = (best * hop + win / 2) / sr
        cuts.append(cut)
        t = cut + chunk_sec
    cuts.append(total)
    return [(cuts[i], cuts[i + 1]) for i in range(len(cuts) - 1)]


def stage_asr(wav: Path, out: Path, chunk_sec: float, language: str):
    import numpy as np
    import torch
    import soundfile as sf
    from transformers import AutoProcessor, CohereAsrForConditionalGeneration

    audio, sr = sf.read(str(wav), dtype="float32")
    if audio.ndim > 1:
        audio = audio.mean(axis=1)
    if sr != 16000:
        die(f"expected 16 kHz wav, got {sr}")

    spans = quiet_split_points(audio, sr, chunk_sec)
    print(f"[asr] {len(audio)/sr:.1f}s -> {len(spans)} chunk(s) split on quiet points", flush=True)

    processor = AutoProcessor.from_pretrained(MODEL_ID)
    model = CohereAsrForConditionalGeneration.from_pretrained(MODEL_ID, dtype=torch.float32)
    dev = "mps" if torch.backends.mps.is_available() else "cpu"
    model = model.to(dev).eval()
    print(f"[asr] model on {dev}", flush=True)

    segments = []
    for i, (s, e) in enumerate(spans):
        clip = audio[int(s * sr):int(e * sr)]
        if len(clip) < sr * 0.2:
            continue
        inputs = processor(clip, sampling_rate=16000, return_tensors="pt", language=language)
        for k in list(inputs.keys()):
            v = inputs[k]
            if isinstance(v, torch.Tensor):
                v = v.to(dev)
                if v.dtype.is_floating_point:
                    v = v.to(model.dtype)
                inputs[k] = v
        with torch.no_grad():
            gen = model.generate(**inputs, max_new_tokens=1024)
        text = " ".join(t.strip() for t in processor.batch_decode(gen, skip_special_tokens=True) if t.strip())
        print(f"[asr] chunk {i+1}/{len(spans)} {s:6.2f}-{e:6.2f}s  {len(text.split())} words", flush=True)
        if text:
            segments.append({"start": round(s, 3), "end": round(e, 3), "text": text})

    out.write_text(json.dumps({"language": language, "segments": segments}, ensure_ascii=False, indent=2))
    print(f"[asr] wrote {out}", flush=True)


# ------------------------------------------------------ stage 2: the timings


def stage_align(wav: Path, text_json: Path, out: Path, language: str):
    import whisperx

    data = json.loads(text_json.read_text())
    segments = [s for s in data["segments"] if s.get("text", "").strip()]
    if not segments:
        die("stage 1 produced no text to align")

    audio = whisperx.load_audio(str(wav))
    model_a, meta = whisperx.load_align_model(language_code=language, device="cpu")
    res = whisperx.align(segments, model_a, meta, audio, "cpu", return_char_alignments=False)

    out_segments = []
    all_words = []
    for s in res["segments"]:
        words = []
        for w in s.get("words", []):
            if w.get("start") is None:
                words.append({"word": w["word"]})
            else:
                words.append({
                    "word": w["word"],
                    "start": round(float(w["start"]), 3),
                    "end": round(float(w["end"]), 3),
                    "score": round(float(w.get("score", 0.0)), 3),
                })
        all_words.extend(words)
        out_segments.append({
            "start": round(float(s["start"]), 3),
            "end": round(float(s["end"]), 3),
            "text": s["text"].strip(),
            "words": words,
        })

    timed = sum(1 for w in all_words if "start" in w)
    payload = {"segments": out_segments, "word_segments": all_words, "language": language}
    out.write_text(json.dumps(payload, ensure_ascii=False, indent=2))
    print(f"[align] {len(all_words)} words, {timed} timed ({100*timed/max(len(all_words),1):.1f}%)", flush=True)
    if timed < len(all_words):
        print(f"[align] NOTE {len(all_words)-timed} word(s) got no timing; downstream interpolates them", flush=True)
    print(f"[align] wrote {out}", flush=True)


# -------------------------------------------------------------- orchestrate


def run_stage(venv: Path, args, label):
    py = venv / "bin" / "python"
    if not py.exists():
        die(f"{label} venv missing at {venv} — run scripts/setup.sh first")
    proc = subprocess.run([str(py), os.path.abspath(__file__)] + args, env=venv_env(venv))
    if proc.returncode != 0:
        die(f"{label} stage failed (exit {proc.returncode})", proc.returncode)


def main():
    ap = argparse.ArgumentParser(description="Arabic transcription with word-level timings")
    ap.add_argument("media", nargs="?", help="audio or video file")
    ap.add_argument("-o", "--out", help="output JSON (default: <media>.ar.json)")
    ap.add_argument("--language", default="ar")
    ap.add_argument("--chunk-sec", type=float, default=25.0)
    ap.add_argument("--keep-wav", action="store_true")
    ap.add_argument("--stage", choices=["asr", "align"], help=argparse.SUPPRESS)
    ap.add_argument("--wav", help=argparse.SUPPRESS)
    ap.add_argument("--text", help=argparse.SUPPRESS)
    a = ap.parse_args()

    if a.stage == "asr":
        return stage_asr(Path(a.wav), Path(a.out), a.chunk_sec, a.language)
    if a.stage == "align":
        return stage_align(Path(a.wav), Path(a.text), Path(a.out), a.language)

    if not a.media:
        ap.error("media file required")
    media = Path(a.media).expanduser().resolve()
    if not media.exists():
        die(f"no such file: {media}")
    out = Path(a.out).expanduser().resolve() if a.out else media.with_suffix(media.suffix + ".ar.json")

    tmp = Path(tempfile.mkdtemp(prefix="arabic-asr-"))
    try:
        wav = tmp / "audio16k.wav"
        text_json = tmp / "text.json"
        extract_wav(media, wav)
        run_stage(ASR_VENV, ["--stage", "asr", "--wav", str(wav), "--out", str(text_json),
                             "--chunk-sec", str(a.chunk_sec), "--language", a.language], "ASR")
        run_stage(WHISPERX_TOOL, ["--stage", "align", "--wav", str(wav), "--text", str(text_json),
                                  "--out", str(out), "--language", a.language], "align")
        if a.keep_wav:
            shutil.copy(wav, out.with_suffix(".wav"))
        print(f"\ntranscribe-ar: {out}")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
