#!/usr/bin/env python3
"""Stop hook: refuse a turn that ends with a plan instead of with work.

Chris, 2026-09-13: "You have standing instructions that you should follow each
end turn?" — after a turn that ended by listing three candidate tasks and asking
which to take. The standing rule is the opposite: end a turn by *starting* the
next item, never by naming it. Hand back work in progress, not a plan.

WHY THIS ONE MAY BLOCK, WHERE reply-guard.py DELIBERATELY DOES NOT.

reply-guard's argument against blocking is exact and correct for what it guards:
withholding a reply that has already been written puts what the model believes
it said out of step with what the reader actually read, and the gap is invisible
from both ends.

This blocks a different thing. A Stop hook that blocks does not withhold the
text already written — that text has been delivered. It *appends*: the model is
handed the reason and carries on working. So the failure reply-guard refuses to
risk is not on the table here. Nothing is eaten; something is added.

WHAT IT CHECKS. Did this turn touch anything? A turn that ran no tool since the
last user message produced no work by definition — it is prose, and if the rule
is "start the next item" then prose alone has broken it. Reading and searching
count: finding where the next item lives is starting it.

WHAT IT DOES NOT CHECK, on purpose. Whether the work was any good, whether the
right item was picked, or whether the user asked a question that deserves a
plain answer. The last of those is why ASK_WORDS exists: a turn that ends in a
question the user actually asked for is not a turn that dodged work.
"""

import json
import re
import sys

# A turn that is answering one of these is allowed to be only words: the user
# asked something, and making them wait for an answer while work is done first
# is worse than the rule this enforces.
ASK_WORDS = re.compile(
    r"\b(what|why|how|which|explain|describe|tell me|remind me|can you explain)\b",
    re.I,
)


def turn_since_last_user(transcript_path):
    """Everything the assistant did since the user last spoke."""
    try:
        with open(transcript_path, encoding="utf-8") as f:
            entries = [json.loads(line) for line in f if line.strip()]
    except (OSError, ValueError):
        return None, None

    turn, last_user = [], ""
    for entry in entries:
        if entry.get("type") == "user":
            content = entry.get("message", {}).get("content", "")
            if isinstance(content, list):
                content = " ".join(
                    part.get("text", "") for part in content if isinstance(part, dict)
                )
            # a tool result arrives as a user entry; it is not the user speaking
            if content.strip():
                turn, last_user = [], content
        elif entry.get("type") == "assistant":
            turn.append(entry)
    return turn, last_user


def used_a_tool(turn):
    for entry in turn:
        content = entry.get("message", {}).get("content", [])
        if not isinstance(content, list):
            continue
        for part in content:
            if isinstance(part, dict) and part.get("type") == "tool_use":
                return True
    return False


def main():
    try:
        event = json.load(sys.stdin)
    except ValueError:
        sys.exit(0)

    # already carrying on from a previous block: never chain, or the turn cannot end
    if event.get("stop_hook_active"):
        sys.exit(0)

    turn, last_user = turn_since_last_user(event.get("transcript_path", ""))
    if turn is None:
        sys.exit(0)
    if used_a_tool(turn):
        sys.exit(0)
    if ASK_WORDS.search(last_user or ""):
        sys.exit(0)

    print(
        "started-the-next-thing: this turn ran no tool, so it ended with a plan "
        "rather than with work. The standing rule is to end a turn by STARTING "
        "the next worklist item — hand back work in progress, not a list of "
        "candidates and a question about which to take. Pick one and begin it.",
        file=sys.stderr,
    )
    sys.exit(2)


main()
