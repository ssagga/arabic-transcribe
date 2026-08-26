#!/usr/bin/env bash
# Turn-key installer for arabic-transcribe.
#
#   curl -fsSL https://raw.githubusercontent.com/ssagga/arabic-transcribe/main/install.sh | bash
#   ./install.sh                 # from a clone
#   ./install.sh --check         # report only, change nothing
#
# Installs the skill for every agent on this machine, then builds the two Python
# environments the pipeline needs. Idempotent: safe to re-run any time.
set -uo pipefail

REPO_URL="https://github.com/ssagga/arabic-transcribe.git"
SKILL="arabic-transcribe"
CANON="$HOME/.agents/skills/$SKILL"
CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

bold()  { printf '\033[1m%s\033[0m\n' "$1"; }
ok()    { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn()  { printf '  \033[33m!\033[0m %s\n' "$1"; }
fail()  { printf '  \033[31m✗\033[0m %s\n' "$1"; }

bold "arabic-transcribe installer"
echo

# ---------------------------------------------------------------- 1. sources
# Running from a clone? Use it. Piped from curl? Clone to a cache dir first.
SRC=""
if [ -f "$(dirname "${BASH_SOURCE[0]:-$0}")/.claude/skills/$SKILL/SKILL.md" ]; then
  SRC="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
  ok "using this clone: $SRC"
else
  SRC="$HOME/.cache/arabic-transcribe-src"
  if [ "$CHECK" = "1" ]; then
    warn "would clone $REPO_URL -> $SRC"
  else
    command -v git >/dev/null 2>&1 || { fail "git is required"; exit 1; }
    if [ -d "$SRC/.git" ]; then git -C "$SRC" pull --ff-only -q || true
    else git clone -q --depth 1 "$REPO_URL" "$SRC" || { fail "clone failed"; exit 1; }; fi
    ok "cloned to $SRC"
  fi
fi

# ------------------------------------------------------------- 2. the skill
# One canonical copy, symlinked into every agent that looks for skills. This is the
# same layout `npx skills add` produces, so the two never fight.
if [ "$CHECK" = "1" ]; then
  warn "would install the skill to $CANON and link it into any agent dirs present"
else
  mkdir -p "$(dirname "$CANON")"
  rm -rf "$CANON"
  cp -R "$SRC/.claude/skills/$SKILL" "$CANON"
  chmod +x "$CANON/scripts/"*.sh "$CANON/scripts/"*.py 2>/dev/null
  ok "skill installed: $CANON"
  linked=0
  for d in "$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.cursor/skills-cursor" \
           "$HOME/.config/agents/skills" "$HOME/.windsurf/skills"; do
    [ -d "$d" ] || continue
    ln -sfn "$CANON" "$d/$SKILL" && { ok "linked into $(basename "$(dirname "$d")")/$(basename "$d")"; linked=$((linked+1)); }
  done
  [ "$linked" = "0" ] && warn "no agent skill directories found — point your agent at $CANON"
fi

# -------------------------------------------------------- 3. the environments
echo
if [ "$CHECK" = "1" ]; then
  bash "$SRC/.claude/skills/$SKILL/scripts/setup.sh" --check
else
  bash "$CANON/scripts/setup.sh"
fi
rc=$?

echo
if [ "$rc" = "0" ]; then
  bold "Ready."
  cat <<EOF

  Transcribe:
    python3 $CANON/scripts/transcribe_ar.py <video-or-audio> -o out.json

  Straight into open-edit (transcript + prep in one step):
    bash $CANON/scripts/openedit.sh <video>

  Check the install any time:
    bash $CANON/scripts/doctor.sh
EOF
else
  bold "Not ready yet — see the notes above."
  echo "  Re-check with: bash $CANON/scripts/doctor.sh"
fi
exit $rc
