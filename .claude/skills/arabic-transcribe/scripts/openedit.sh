#!/usr/bin/env bash
# Arabic video -> a prepped open-edit run, in one command.
#
#   ./openedit.sh <video> [--root /path/to/open-edit] [--keep-json out.json]
#
# Does the three steps by hand so nothing is guessed:
#   1. transcribe_ar.py       -> Whisper-family JSON with per-word timings
#   2. prep/whisper.ts        -> runs/<key>/transcript.json   (the `custom` provider seam)
#   3. prep/prep.ts           -> meta.json + word-timings.json + beat frames
#
# Then prints the next command in the open-edit flow. It deliberately does NOT
# rewrite the recorded transcription provider: that preference is global, and
# setting it to `custom` would route English clips here too.
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VIDEO=""; ROOT=""; KEEP=""

while [ $# -gt 0 ]; do
  case "$1" in
    --root)      ROOT="$2"; shift 2;;
    --keep-json) KEEP="$2"; shift 2;;
    -h|--help)   sed -n '2,12p' "$0"; exit 0;;
    *)           VIDEO="$1"; shift;;
  esac
done

die() { printf '\033[31mopenedit:\033[0m %s\n' "$1" >&2; exit 1; }
say() { printf '\033[1mopenedit:\033[0m %s\n' "$1"; }

[ -n "$VIDEO" ] || die "usage: openedit.sh <video> [--root <open-edit root>]"
[ -f "$VIDEO" ] || die "no such file: $VIDEO"
VIDEO="$(cd "$(dirname "$VIDEO")" && pwd)/$(basename "$VIDEO")"

# ---- find the open-edit runtime -------------------------------------------
if [ -z "$ROOT" ]; then
  for c in "${OPEN_EDIT_ROOT:-}" "$PWD/.open-edit/runtime" "$PWD/../.open-edit/runtime" \
           "$PWD/../../.open-edit/runtime" "$HOME/.open-edit/runtime"; do
    [ -n "${c:-}" ] && [ -f "$c/prep/whisper.ts" ] && { ROOT="$c"; break; }
  done
fi
[ -n "$ROOT" ] && [ -f "$ROOT/prep/whisper.ts" ] || die "open-edit runtime not found — pass --root <path>
  (it is the directory holding prep/whisper.ts, usually <project>/.open-edit/runtime)"
ROOT="$(cd "$ROOT" && pwd)"
say "runtime: $ROOT"

# ---- node ------------------------------------------------------------------
# The runtime itself is happy on Node 20.11 (verified: tsx loads, scripts run).
# Only the separate `npx skills add` CLI needs >= 20.12, so this is not a gate.
command -v node >/dev/null 2>&1 || die "node is required by the open-edit runtime"

# ---- 1. transcribe --------------------------------------------------------
JSON="${KEEP:-$(mktemp -d)/ar.json}"
say "transcribing (Arabic, word-timed)…"
python3 "$SELF/transcribe_ar.py" "$VIDEO" -o "$JSON" || die "transcription failed"

# ---- 2 + 3. into the pipeline ---------------------------------------------
say "mapping into open-edit…"
( cd "$ROOT" && node --import tsx prep/whisper.ts "$JSON" "$VIDEO" ) || die "prep/whisper.ts failed"
( cd "$ROOT" && node --import tsx prep/prep.ts "$VIDEO" ) || die "prep/prep.ts failed"

KEY="$(basename "${VIDEO%.*}" | tr ' ' '_')"
echo
say "run ready: $ROOT/runs/$KEY"
cat <<EOF

  Next, in $ROOT:

    node --import tsx pipeline/scripts/sample-style.ts --run runs/$KEY
    node --import tsx pipeline/scripts/generate-recipe.ts --run runs/$KEY --record
    node --import tsx pipeline/scripts/mux-audio.ts runs/$KEY

  BEFORE you design Arabic captions, read:
    $SELF/../references/arabic-captions.md

  The stock recipes are built for Latin type. Arabic needs an Arabic face and,
  if captions are split per word for a reveal, the span order REVERSED — the
  engine does not reorder inline-block boxes for direction:rtl. Skipping that
  gives you a video whose every sentence reads backwards.
EOF
