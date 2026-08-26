#!/usr/bin/env python3
"""Recover a session's prompts and replies from a Claude Code transcript.

WHY THIS EXISTS
---------------
The UserPromptSubmit / Stop hooks that write docs/prompt-log/ load at SESSION
START. They were added mid-session on 2026-08-15, so the very session that
designed them captured nothing: three days of decisions, Tara's real schedule,
and every judgement call, none of it logged. Exactly the failure the log was
built to prevent.

The transcript is still on disk, so this recovers it. Run it once per session
that predates the hooks; after that the hooks do it live and this is only
needed to repair a gap.

USAGE
    python3 scripts/backfill-prompt-log.py <transcript.jsonl> [--write]

Without --write it prints a summary and changes nothing.

REDACTION IS NOT OPTIONAL
-------------------------
docs/prompt-log/ is committed to git, and git history is very hard to scrub.
Tara forwards real club emails carrying hundreds of members' addresses. Those
people gave her an address for clinic scheduling, not for a GitHub repository.
Every email address is replaced with a placeholder except obvious test domains.
What matters for future context is what was DECIDED, never the addresses.
"""
import json, re, sys, os
from collections import Counter

EMAIL = re.compile(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b')
# Fake domains used in seeds and tests: safe, and useful to keep readable.
KEEP = re.compile(r'@(fxe\.test|example\.test|example\.com)$', re.I)

def redact(text, counter):
    def sub(m):
        if KEEP.search(m.group(0)):
            return m.group(0)
        counter['emails'] += 1
        return '[email redacted]'
    return EMAIL.sub(sub, text)

def blocks_to_text(content):
    if isinstance(content, str):
        return content
    out = []
    for b in content or []:
        if isinstance(b, dict) and b.get('type') == 'text' and b.get('text', '').strip():
            out.append(b['text'])
    return "\n\n".join(out)

def is_real_user_turn(entry):
    """A user entry that is an actual typed prompt, not a tool result."""
    msg = entry.get('message') or {}
    c = msg.get('content')
    if isinstance(c, str):
        return bool(c.strip())
    for b in c or []:
        if isinstance(b, dict) and b.get('type') == 'tool_result':
            return False
    return bool(blocks_to_text(c).strip())

def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    path, write = sys.argv[1], '--write' in sys.argv
    counter = Counter()
    turns = []

    with open(path, encoding='utf-8', errors='replace') as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                e = json.loads(line)
            except Exception:
                counter['unparseable'] += 1
                continue
            t = e.get('type')
            if t == 'user' and is_real_user_turn(e):
                txt = blocks_to_text((e.get('message') or {}).get('content'))
                # System-injected reminders are not things Alex typed.
                if '<system-reminder>' in txt and len(txt) < 2000:
                    continue
                turns.append(('prompt', e.get('timestamp', ''), txt))
                counter['prompts'] += 1
            elif t == 'assistant':
                txt = blocks_to_text((e.get('message') or {}).get('content'))
                if txt.strip():
                    turns.append(('reply', e.get('timestamp', ''), txt))
                    counter['replies'] += 1

    print(f"prompts: {counter['prompts']}  replies: {counter['replies']}  "
          f"unparseable lines: {counter['unparseable']}")

    if not write:
        print("\nDry run. Re-run with --write to append to docs/prompt-log/.")
        return

    out = "docs/prompt-log/2026-08-backfilled.md"
    os.makedirs("docs/prompt-log", exist_ok=True)
    with open(out, 'w', encoding='utf-8') as f:
        f.write("# Prompt log: 2026-08 (backfilled from transcript)\n\n"
                "Recovered by `scripts/backfill-prompt-log.py` because the logging hooks\n"
                "were added mid-session and load only at session start, so this session\n"
                "captured nothing live. Newest at the bottom.\n\n"
                "**Email addresses are redacted.** Tara forwards real club rosters and this\n"
                "file is committed. Test domains are kept readable.\n")
        for kind, ts, txt in turns:
            head = "## Alex" if kind == 'prompt' else "### Claude replied"
            f.write(f"\n---\n\n{head} · {ts}\n\n~~~~text\n{redact(txt, counter)}\n~~~~\n")

    print(f"wrote {out}  ({counter['emails']} email addresses redacted)")

if __name__ == '__main__':
    main()
