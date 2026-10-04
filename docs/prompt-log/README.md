# Prompt log (local only)

The logging hooks (`.claude/hooks/log-prompt.sh`, `.claude/hooks/log-response.sh`)
write every prompt and reply into this folder, one file per month. Since
2026-10-04 those files are **not committed**: the repository is public, and a
chat about a real business carries real people's details (twice now, a person's
tax and identity details were pasted in and had to be scrubbed by hand before a
commit). They live on Alex's Mac only; `.gitignore` keeps them out.

Logs committed before 2026-10-04 remain in the history, scrubbed of what the
hooks and two hand passes caught.
