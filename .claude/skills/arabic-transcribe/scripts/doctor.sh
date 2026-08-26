#!/usr/bin/env bash
# Diagnose the install and every trap this pipeline is known to hit.
# Changes nothing. Exit 0 = ready to transcribe.
#
#   ./doctor.sh            checks
#   ./doctor.sh <media>    checks, then a real end-to-end transcription of that file
set -uo pipefail

ASR_VENV="$HOME/.local/share/arabic-asr/asr-venv"
WX_ROOT="$HOME/.local/share/uv/tools/whisperx"
MODEL_ID="CohereLabs/cohere-transcribe-arabic-07-2026"
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
problems=0

ok()   { printf '  \033[32m✓\033[0m %-30s %s\n' "$1" "${2:-}"; }
bad()  { printf '  \033[31m✗\033[0m %-30s %s\n' "$1" "${2:-}"; problems=$((problems+1)); }
note() { printf '    \033[2m%s\033[0m\n' "$1"; }

echo "arabic-transcribe doctor"
echo

# ---- tools ----------------------------------------------------------------
command -v ffmpeg  >/dev/null 2>&1 && ok "ffmpeg"  "$(ffmpeg -version 2>/dev/null | head -1 | awk '{print $3}')" \
                                   || bad "ffmpeg"  "not on PATH"
command -v ffprobe >/dev/null 2>&1 && ok "ffprobe" || bad "ffprobe" "not on PATH"
command -v uv      >/dev/null 2>&1 && ok "uv" "$(uv --version 2>/dev/null | awk '{print $2}')" \
                                   || bad "uv" "not on PATH"

# ---- the two environments -------------------------------------------------
if [ -x "$ASR_VENV/bin/python" ]; then
  TV="$("$ASR_VENV/bin/python" -c 'import transformers;print(transformers.__version__)' 2>/dev/null)"
  if "$ASR_VENV/bin/python" -c "from transformers import CohereAsrForConditionalGeneration" 2>/dev/null; then
    ok "ASR env" "transformers $TV"
  else
    bad "ASR env" "transformers ${TV:-?} has no CohereAsr class — needs >= 5.4"
  fi
else
  bad "ASR env" "missing — run setup.sh"
fi

if [ -x "$WX_ROOT/bin/python" ] && "$WX_ROOT/bin/python" -c "import whisperx" 2>/dev/null; then
  ok "aligner (whisperx)"
else
  bad "aligner (whisperx)" "missing — run setup.sh"
fi

# ---- TRAP 1: macOS python.org builds ship no CA store ---------------------
# Symptom: CERTIFICATE_VERIFY_FAILED while downloading the alignment model.
if [ -x "$ASR_VENV/bin/python" ]; then
  CERT="$(ls "$ASR_VENV"/lib/python*/site-packages/certifi/cacert.pem 2>/dev/null | head -1)"
  if [ -n "$CERT" ]; then ok "TLS certificates" "certifi bundle present"
  else bad "TLS certificates" "no certifi in the ASR env — TLS downloads may fail"
       note "the transcriber sets SSL_CERT_FILE itself; outside it, export it manually"; fi
fi

# ---- TRAP 2: the model is gated ------------------------------------------
if [ -x "$ASR_VENV/bin/python" ]; then
  if "$ASR_VENV/bin/python" - <<PY 2>/dev/null
from huggingface_hub import HfApi
import sys
try: HfApi().model_info("$MODEL_ID")
except Exception: sys.exit(1)
PY
  then ok "model access" "gate accepted, token present"
  else bad "model access" "401 / gated"
       note "1. accept: https://huggingface.co/$MODEL_ID"
       note "2. login:  $ASR_VENV/bin/hf auth login"; fi
fi

# ---- TRAP 3: GPU or CPU ---------------------------------------------------
if [ -x "$ASR_VENV/bin/python" ]; then
  ACC="$("$ASR_VENV/bin/python" -c "
import torch
print('mps' if torch.backends.mps.is_available() else ('cuda' if torch.cuda.is_available() else 'cpu'))" 2>/dev/null)"
  case "$ACC" in
    mps|cuda) ok "acceleration" "$ACC (~7x realtime)";;
    cpu)      ok "acceleration" "cpu — expect roughly realtime, not a failure";;
    *)        bad "acceleration" "could not query torch";;
  esac
fi

# ---- TRAP 4: weights cached? ---------------------------------------------
CACHE="$HOME/.cache/huggingface/hub/models--CohereLabs--cohere-transcribe-arabic-07-2026"
[ -d "$CACHE" ] && ok "model weights" "cached ($(du -sh "$CACHE" 2>/dev/null | cut -f1))" \
                || ok "model weights" "not cached — first run downloads 4.13 GB"

# ---- TRAP 5: disk ---------------------------------------------------------
FREE_G="$(df -Pg "$HOME" 2>/dev/null | awk 'NR==2{print $4}')"
if [ -n "$FREE_G" ]; then
  [ "$FREE_G" -ge 12 ] && ok "disk free" "${FREE_G} GB" || bad "disk free" "${FREE_G} GB — needs ~10 GB"
fi

# ---- informational: Node, only if you install via `npx skills add` --------
if command -v node >/dev/null 2>&1; then
  NV="$(node -v | sed 's/^v//')"
  MAJ="${NV%%.*}"; REST="${NV#*.}"; MIN="${REST%%.*}"
  if [ "$MAJ" -gt 20 ] 2>/dev/null || { [ "$MAJ" -eq 20 ] && [ "$MIN" -ge 12 ]; } 2>/dev/null; then
    ok "node (optional)" "v$NV"
  else
    ok "node (optional)" "v$NV — fine for this tool"
    note "but 'npx skills add' needs >= 20.12 (it imports node:util styleText and crashes below that)"
    note "this pipeline is pure Python and does not care"
  fi
fi

echo
if [ "$problems" = "0" ]; then echo "ready."; else echo "$problems problem(s) — see above."; fi

# ---- optional end-to-end run ---------------------------------------------
if [ -n "${1:-}" ] && [ "$problems" = "0" ]; then
  echo
  echo "end-to-end test on $1"
  OUT="$(mktemp -d)/doctor.json"
  python3 "$SELF/transcribe_ar.py" "$1" -o "$OUT" 2>&1 | grep -E "^\[asr\]|^\[align\]" || true
  if [ -f "$OUT" ]; then
    "$ASR_VENV/bin/python" - "$OUT" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
w=[x for s in d["segments"] for x in s.get("words",[])]
t=sum(1 for x in w if "start" in x)
print(f"  words {len(w)} | timed {t} ({100*t/max(len(w),1):.1f}%)")
print("  first line:", (d["segments"][0]["text"][:70] if d["segments"] else "(empty)"))
PY
  else
    echo "  transcription produced no output"; problems=1
  fi
fi

[ "$problems" = "0" ]
