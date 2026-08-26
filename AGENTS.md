# AGENTS.md

Arabic speech → text with **per-word timings**, for agents that caption or edit video.

The skill lives at `.claude/skills/arabic-transcribe/SKILL.md`. Read it before use.

## Quick reference

```bash
# transcript with word timings
python3 ~/.agents/skills/arabic-transcribe/scripts/transcribe_ar.py <media> -o out.json

# Arabic video -> prepped open-edit run, one command
bash ~/.agents/skills/arabic-transcribe/scripts/openedit.sh <video>

# is anything broken?
bash ~/.agents/skills/arabic-transcribe/scripts/doctor.sh
```

## Rules that matter

- **The gate is the user's.** The model is gated on HuggingFace. Accepting the terms
  and running `hf auth login` are the user's to do. Never ask for their token in chat.
- **Do not merge the two virtualenvs.** The model needs transformers >= 5.4; WhisperX
  pins 4.x. They exchange JSON on disk on purpose.
- **Do not rewrite open-edit's recorded transcription provider** to `custom` unless the
  user works almost entirely in Arabic — that preference is global and would route
  their English clips here too.
- **Read `references/arabic-captions.md` before designing any Arabic caption.** A
  correct transcript does not give you a correct video. Per-word spans render in
  reverse in the weave engine: every word right, every sentence backwards, and it
  passes every automated gate. Use `helpers/rtl-spans.mjs`.
- **Verify by rendering, not by reasoning.** `examples/rtl-control-render` exists
  because the CSS spec and this engine disagree.
