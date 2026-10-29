#!/usr/bin/env python3
"""Stop hook: refuse a reply that is unstamped or over-long.

Chris, 2026-08-27: "how can I enable a feature and make sure it is always used
mechanically?" A skill cannot be. It is text in the model's context and nothing
checks the output against it — the caveman hooks delivered the rule on every
single turn and the replies were walls of text anyway. The delivery was never
the gap.

A Stop hook runs when a turn ends. It CAN block with exit 2 — and this one
deliberately does not.

WHY IT ONLY WARNS. Chris, same conversation: "you think you responded, I'm
complaining that you didn't respond." Blocking a reply that has already been
written puts what the model believes it said out of step with what the user
actually read, and neither of us can see that gap from where we stand. The
failure it risks is silent and it lands on the reader. A warning cannot do
that: the reply is delivered untouched, and the notice appears beside it.

So this reports and never withholds. Enforcement that can eat a reply is worse
than a rule nobody enforces.

WHAT IT CHECKS, deliberately only two things:

  1. a timestamp on the first non-empty line
  2. prose lines under a limit

WHAT IT DOES NOT COUNT, and this is the whole reason it is safe to leave on:
fenced code, tables, and blockquotes. Those are the measurements — mutation
matrices, gate rows, shas, command output — and this repository's standing rule
is to cut around evidence, never the evidence itself. A guard that punished a
table would teach its author to stop pasting them, which is the opposite of
what it is for.
"""

import json
import os
import re
import sys

PROSE_LINE_LIMIT = int(os.environ.get("REPLY_GUARD_PROSE_LINES", "30"))

# 2026-08-27 09:38 CEST, with or without surrounding bold.
STAMP = re.compile(r"\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}(\s+[A-Z]{2,5})?")


def last_assistant_text(transcript_path):
    """The text of the most recent assistant message, or None."""
    try:
        with open(transcript_path, encoding="utf-8") as f:
            lines = f.readlines()
    except OSError:
        return None

    for line in reversed(lines):
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if entry.get("type") != "assistant":
            continue
        content = entry.get("message", {}).get("content", [])
        if isinstance(content, str):
            return content
        parts = [c.get("text", "") for c in content if isinstance(c, dict) and c.get("type") == "text"]
        text = "\n".join(p for p in parts if p).strip()
        # A turn can end on a tool call with no prose. Nothing to judge.
        return text or None
    return None


def prose_lines(text):
    """Lines that are prose: not fenced code, not a table, not a quote."""
    out, fenced = [], False
    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith("```"):
            fenced = not fenced
            continue
        if fenced or not line:
            continue
        if line.startswith("|") or line.startswith(">"):
            continue
        # A markdown table's rule row, e.g. |---|---|
        if set(line) <= set("|-: "):
            continue
        out.append(line)
    return out


def main():
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        sys.exit(0)

    text = last_assistant_text(payload.get("transcript_path", ""))
    if not text:
        sys.exit(0)

    complaints = []

    first = next((l for l in text.splitlines() if l.strip()), "")
    if not STAMP.search(first):
        complaints.append(
            "No timestamp. Start the reply with the current local time — run "
            "`date '+%Y-%m-%d %H:%M %Z'`, do not guess it and do not reuse an "
            "earlier one."
        )

    lines = prose_lines(text)
    if len(lines) > PROSE_LINE_LIMIT:
        complaints.append(
            f"{len(lines)} prose lines, limit {PROSE_LINE_LIMIT}. Code blocks, "
            "tables and quotes are already excluded, so this is prose alone. "
            "Cut restatement, preamble, and reasoning that was not asked for. "
            "Keep the measurements, the shas, and what a green does NOT mean."
        )

    if complaints:
        # stdout JSON, exit 0. The reply is already delivered and stays that way;
        # this only puts a note next to it.
        print(json.dumps({"systemMessage": "reply-guard: " + "; ".join(complaints)}))
    sys.exit(0)


if __name__ == "__main__":
    main()
