#!/usr/bin/env python3
"""Stop hook: hand back the next unticked task instead of letting the turn end.

Chris, 2026-09-13: "controlling a markdown file full of tasks — would that work?"
It does, and the reason it does is the bit that is easy to get wrong: a Stop
hook fires AFTER the reply has been delivered. Exit 2 does not retract or
suppress anything already written. It refuses to let the *turn* end, and stderr
comes back as the next instruction. So the user reads the whole of the previous
turn, and then the model carries on. Nothing is swallowed; a turn is appended.

The stop condition is the list itself: no unticked entries, exit 0, done.

WHAT IT WILL NOT DO, and this is the honest part. It forces the model to keep
going. It cannot make what happens next any good, and it cannot tell work from
the appearance of work — a model that ticks a box and stops has satisfied it
exactly as well as one that did the job. So it asks for evidence rather than for
a tick: something has to have been committed since the turn began, or the same
task comes back with a note saying so. That is still not a quality check. It is
the difference between "you said you did it" and "the repository changed".

SAFETY. `stop_hook_active` is honoured, so it never chains inside one stop.
MAX_BOUNCES caps a runaway at a number you can see and change. Ctrl-C always
wins. If the list is long and the work is real, this will run for a long time
and spend accordingly — that is the point of it, and it is worth knowing before
switching it on.
"""

import json
import os
import re
import subprocess
import sys
from pathlib import Path

LIST = Path(os.environ.get("TASK_LIST", "docs/worklist.md"))
MAX_BOUNCES = int(os.environ.get("TASK_LOOP_MAX", "40"))
COUNTER = Path(".git/.task-loop-bounces")
LAST_HEAD = Path(".git/.task-loop-head")

# `- [ ] **12. Title.** ...` or plain `- [ ] Title`
UNTICKED = re.compile(r"^- \[ \]\s+(?:\*\*(?P<num>[\w.-]+)\.\s*)?(?P<title>.+?)(?:\*\*|$)", re.M)


def next_task():
    try:
        text = LIST.read_text(encoding="utf-8")
    except OSError:
        return None
    m = UNTICKED.search(text)
    if not m:
        return None
    num = m.group("num")
    title = m.group("title").strip().rstrip("*").strip()
    return f"{num}. {title}" if num else title


def head():
    """What the repository is sitting on, or None where there is no repository."""
    try:
        return subprocess.run(
            ["git", "rev-parse", "HEAD"], capture_output=True, text=True, check=True
        ).stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None


def main():
    try:
        event = json.load(sys.stdin)
    except ValueError:
        sys.exit(0)

    if event.get("stop_hook_active"):
        sys.exit(0)

    task = next_task()
    if task is None:
        COUNTER.unlink(missing_ok=True)
        LAST_HEAD.unlink(missing_ok=True)
        sys.exit(0)                      # the list is empty: this is what done looks like

    was = LAST_HEAD.read_text().strip() if LAST_HEAD.exists() else None
    now = head()
    # nothing landed since the last bounce: say so rather than asking again as though it had
    idle = "" if was is None or now is None or now != was else (
        "\n\nNothing has been committed since the last time this asked, so the turn before it "
        "produced no work that survives. If the task is blocked, say which decision it is waiting "
        "on and mark it blocked; otherwise start it properly rather than describing it."
    )
    if now:
        LAST_HEAD.write_text(now)

    bounces = int(COUNTER.read_text()) if COUNTER.exists() else 0
    if bounces >= MAX_BOUNCES:
        COUNTER.unlink(missing_ok=True)
        print(
            f"next-unticked: stopping after {bounces} turns with work still on the list. "
            "Raise TASK_LOOP_MAX or clear the run counter to continue.",
            file=sys.stderr,
        )
        sys.exit(0)
    COUNTER.write_text(str(bounces + 1))

    print(
        f"next-unticked: {LIST} still has unticked work, and the standing rule is to end a "
        f"turn by starting the next item rather than by naming it.\n\n"
        f"The next one is: {task}\n\n"
        "Start it. If it is genuinely blocked on a decision only the user can make, say so in "
        "one line, tick it as blocked in the list so it stops coming back, and take the one "
        "after it. Do not tick anything you have not actually done — the repository is what is "
        "read, not the box." + idle,
        file=sys.stderr,
    )
    sys.exit(2)


main()
