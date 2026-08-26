#!/usr/bin/env bash
# Idempotent environment bootstrap. Safe to re-run.
#
#   ./setup.sh          verify, install what is missing
#   ./setup.sh --check  report only, install nothing
#
# Two Python environments, deliberately separate — see references/troubleshooting.md.
set -uo pipefail

CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

ASR_VENV="$HOME/.local/share/arabic-asr/asr-venv"
MODEL_ID="CohereLabs/cohere-transcribe-arabic-07-2026"
ok=1

say()  { printf '  %-26s %s\n' "$1" "$2"; }
need() { [ "$CHECK_ONLY" = "1" ] && { ok=0; return 1; }; return 0; }

pkg_install() {  # $1 = brew formula, $2 = apt package
  if command -v brew >/dev/null 2>&1; then brew install "$1"
  elif command -v apt-get >/dev/null 2>&1; then sudo apt-get update -qq && sudo apt-get install -y "$2"
  else return 1; fi
}

echo "arabic-transcribe setup"
echo

# ---- ffmpeg ---------------------------------------------------------------
if command -v ffmpeg >/dev/null 2>&1; then
  say "ffmpeg" "ok ($(ffmpeg -version 2>/dev/null | head -1 | awk '{print $3}'))"
else
  say "ffmpeg" "MISSING"
  if need; then pkg_install ffmpeg ffmpeg || { echo "    install ffmpeg manually"; ok=0; }; fi
fi

# ---- uv (creates both isolated environments) ------------------------------
if command -v uv >/dev/null 2>&1; then
  say "uv" "ok ($(uv --version 2>/dev/null | awk '{print $2}'))"
else
  say "uv" "MISSING"
  if need; then
    pkg_install uv uv || curl -LsSf https://astral.sh/uv/install.sh | sh || ok=0
    export PATH="$HOME/.local/bin:$PATH"
  fi
fi

# ---- ASR venv: transformers >= 5.4 for the Cohere model -------------------
if [ -x "$ASR_VENV/bin/python" ] && \
   "$ASR_VENV/bin/python" -c "from transformers import CohereAsrForConditionalGeneration" 2>/dev/null; then
  say "ASR env" "ok (transformers $("$ASR_VENV/bin/python" -c 'import transformers;print(transformers.__version__)' 2>/dev/null))"
else
  say "ASR env" "MISSING or too old"
  if need; then
    echo "    building $ASR_VENV (~4 GB with torch)"
    mkdir -p "$(dirname "$ASR_VENV")"
    uv venv "$ASR_VENV" --python 3.12 || ok=0
    uv pip install --python "$ASR_VENV/bin/python" \
      "transformers>=5.4.0" torch huggingface_hub soundfile librosa \
      sentencepiece protobuf accelerate numpy || ok=0
  fi
fi

# ---- WhisperX: supplies the Arabic forced aligner -------------------------
# Pinned to transformers 4.x, which is why it cannot share the venv above.
WHISPERX_PY="$(command -v whisperx >/dev/null 2>&1 && echo found || echo '')"
WX_ROOT="$HOME/.local/share/uv/tools/whisperx"
if [ -x "$WX_ROOT/bin/python" ] && "$WX_ROOT/bin/python" -c "import whisperx" 2>/dev/null; then
  say "aligner (whisperx)" "ok"
else
  say "aligner (whisperx)" "MISSING"
  if need; then
    echo "    uv tool install whisperx (~2 GB)"
    uv tool install whisperx || ok=0
  fi
fi

# ---- HuggingFace access to the gated model --------------------------------
if [ -x "$ASR_VENV/bin/python" ]; then
  if "$ASR_VENV/bin/python" - <<PY 2>/dev/null
from huggingface_hub import HfApi
import sys
try: HfApi().model_info("$MODEL_ID")
except Exception: sys.exit(1)
PY
  then
    say "model access" "ok"
  else
    say "model access" "BLOCKED (gated)"
    ok=0
    cat <<EOF

  The model is gated. Both steps are yours — nothing here can do them for you:

    1. Accept the terms (instant, auto-approved):
       https://huggingface.co/$MODEL_ID

    2. Log in on this machine:
       $ASR_VENV/bin/hf auth login

       or, if you prefer an environment variable:
       export HF_TOKEN=...        # from https://huggingface.co/settings/tokens (read scope)
EOF
  fi
else
  say "model access" "skipped (no env yet)"
fi

echo
if [ "$ok" = "1" ]; then
  echo "ready."
else
  [ "$CHECK_ONLY" = "1" ] && echo "not ready — re-run without --check to install." \
                          || echo "not ready — see the notes above."
  exit 1
fi
