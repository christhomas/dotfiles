---
name: documentation-protocol
description: Persistent findings document that records, per iteration, the symptom observed, the evidence gathered, the change made, and the result. Use whenever you're working through a multi-iteration debug/discovery loop where the *rationale* for each change matters more than the change itself, where the work spans multiple sessions or contributors, or where future readers will need to understand why a specific byte/field/value is what it is. Composes with dev-loop (which guards behavioural correctness via the test contract) and corroborated-debug (which guards each change's evidentiary basis) — this skill is the third leg, guarding institutional memory across sessions.
---

# Documentation Protocol

## File-edit collision guard (mandatory)

The findings document is a **shared, multi-writer** file — multiple sessions and contributors append to it. Before each write:

1. **On read** — record the document's content hash (`shasum -a 256 <file>`) as your baseline.
2. **Before you write** — recompute the on-disk hash; proceed only if it still matches.
3. **If it differs** — another writer appended since you read it. **Do NOT overwrite the whole file.** Re-read, then `Edit` in your new iteration entry surgically, preserving everything they added.
4. **Prefer `Edit` (append/insert) over full-file `Write`** for the findings doc, always.
5. **Never delete an entry or file** without explicit user confirmation.

This closes the lost-update race where one session's iteration log silently clobbers another's. (Same contract as the dev-loop skill this composes with.)

A discipline for writing down *why* each change was made — not what the change was (the diff shows that) but the evidence that justified it, so the rationale survives the session.

## Why this skill exists

Three failure modes recur in long debug loops:

1. **The agent makes a change but six months later nobody remembers why.** A reviewer reads `rec[at + 22] = 1` and has no idea if removing it would break things. The original conversation is gone; the commit message says "fix corruption". The change is now load-bearing for unknown reasons.
2. **The session ends mid-investigation.** Tomorrow's session has to re-derive what we already knew. The reproduction steps, the diff harness, the iteration history — all gone.
3. **Multiple iterations attack the same root cause from different angles**, each fixing a symptom of the same underlying bug. Without a per-iteration log, we can't see the pattern; we keep adding patches instead of identifying the pattern and fixing once.

This skill solves all three by mandating a single document per debugging area, updated every iteration, that captures the loop's full state.

## What the document is

One markdown file, lives in the project (typically `docs/<area>-findings.md` or wherever the project keeps engineering docs). It is **part of the deliverable**, not optional decoration. A PR that introduces a non-trivial change without updating the relevant findings document is incomplete.

The document has three parts:

1. **Header** — explains what corroboration mechanism is in use (where the diff comes from, what artifacts to look at). A new reader should be able to reproduce the loop from this section alone.
2. **Per-iteration log** — append-only history. Each iteration gets a section: the symptom we hit, the evidence we gathered, the change we made, the result.
3. **What we learned** — generalisable lessons that should inform similar work elsewhere in the codebase or in future projects. This is where institutional memory accrues.

## When to start one

Start a findings document when **either** of these is true:

- You're inside a multi-iteration loop (3+ iterations expected) and have no place to log what each iteration revealed.
- You're making a change whose *rationale* would be opaque to a reader who didn't see the conversation — typically a magic-byte fix, a non-obvious flag, an off-by-one that looks wrong but isn't.

Don't start one for: routine bug fixes where the diff explains itself; refactors where there's nothing to learn; dependency bumps; doc-only changes.

## Per-iteration entry template

Each iteration adds a section like this. **Append, never edit prior iterations** — the history is the value. If you discover an earlier iteration's diagnosis was wrong, add a new iteration that says so; don't rewrite history.

```markdown
### iter<N>: <one-line summary of the iteration's outcome>

**Symptom**

> Verbatim error output. Don't paraphrase — exact wording matters for grep.

**Diagnostic**

What we ran, what data we captured. Link the artifact (CI run id, local diag dir, etc.).

**Per-field diff** *(if a corroboration mechanism exists — see corroborated-debug)*

| Field | reference | ours | spec citation |
|-------|-----------|------|---------------|
| ...   | ...       | ...  | ...           |

**Root cause**

One paragraph. Cite both the diff and the public spec.

**Fix**

Link to commit. Single-line description of the change.

**Result**

Did the targeted error go away? Did anything else change? What does the *next* iteration need to address?
```

The "Result" line of iteration N is what motivates iteration N+1. Each entry both closes one investigation and opens the next.

## What the header should explain

A new reader landing on this file at any point should be able to answer:

- **What problem are we solving?** One paragraph at the top.
- **What's the corroboration mechanism?** Where does our reference output come from? How do we run our output? How do we diff them? What artifacts get produced and where do they live? If `corroborated-debug` is in use, this section describes the harness it builds.
- **What's the test contract?** What is "correct" defined as? If `dev-loop` is in use, link to the baseline file.
- **Where is each iteration's evidence stored?** GitHub Actions run IDs, local artifact paths, etc.

The header should be ~half a page. Not exhaustive, but enough that someone with no prior context can pick up where we left off.

## What "what we learned" is for

This is the section that justifies the document existing across project boundaries.

After several iterations, patterns emerge that aren't specific to the bug being chased. They're observations about: how the validator behaves, which fields it actually checks vs ignores, where the public spec is misleading, what diagnostic noise to ignore, what to instrument first next time.

Write these down as bullet points in plain language. They should be genuinely portable: someone working on a *different* project that uses the same validator/format/protocol should be able to read these bullets and skip past mistakes you already made.

Examples of good "learned" entries (from real projects):

- "Microsoft chkdsk's read-only mode requires shadow-copy storage on volumes ≥ 256 MiB; smaller volumes silently fall back to error-level output that hides specific corruption messages."
- "When porting between glibc and musl, default thread stack size differs — musl is 80 KiB, glibc is 8 MiB. Anything that recurses or holds large stack frames will mysteriously segfault on musl."

Examples of bad "learned" entries (project-specific, belong in iteration log):

- "We had to set `indexed_flag = 1` in `write_file_name`." — too specific; this is in the per-iteration entry already.
- "Iteration 7 took 2 minutes." — irrelevant.

## Composition

This skill works alongside, not instead of, two others. The roles:

- **`dev-loop`** — guards behavioural correctness. Establishes a baseline of passing tests; every change must keep them passing. Catches the failure mode "change broke an unrelated test." Lives in test commands and CI.
- **`corroborated-debug`** — guards each change's evidentiary basis. Each change must come from a byte-diff against a reference, not from a hypothesis. Catches the failure mode "we changed something on a guess and don't know if it actually helped." Lives in diff harnesses and per-iteration evidence.
- **`documentation-protocol`** *(this skill)* — guards institutional memory. The findings document captures *why* each change was made so the rationale survives across sessions and contributors. Catches the failure mode "the original investigator left and now nobody knows what this magic value is for." Lives in `docs/<area>-findings.md`.

A loop that uses all three:

1. `dev-loop` Phase 0–2: establish the test baseline.
2. **`documentation-protocol`: open `docs/<area>-findings.md`, write the header.**
3. `dev-loop` Phase 3: analyse the task. **`documentation-protocol`: this becomes iter1's "Symptom" / "Diagnostic" / "Root cause" sections.**
4. `corroborated-debug` Phases 1–6: gather evidence, make the change, verify it. **`documentation-protocol`: iter1's "Fix" and "Result".**
5. `dev-loop` Phase 5: confirm baseline still passes.
6. **`documentation-protocol`: write iter2's header and continue.** Or, if done, write the "What we learned" section.
7. Loop back to step 3 (next iteration) or step 8 (done).
8. `dev-loop` Phase 7+: final verification, lint, summarise. **`documentation-protocol`: link the doc from the PR description.**

## Anti-patterns

- **Editing prior iterations** to "make them right." The wrongness *is the value* — it shows the path through the problem. Add a new iteration that supersedes the wrong one if needed.
- **Combining unrelated investigations** into one document. One bug area, one document. If you're investigating two unrelated symptoms, that's two documents.
- **Writing the document at the end** as a polished retrospective. The whole point is per-iteration durability — by the time you're polishing at the end, you've forgotten what each iteration's artifact actually showed. Update during the loop, not after.
- **Treating the doc as code-review noise** — "I'll add it later." Later doesn't come. The PR is the trigger; without the doc updated, the PR is incomplete by this protocol.
- **Documenting *what* without *why*.** "Set indexed_flag = 1" is what; the diff table showing every reference record has 1 and every ours has 0 is why. Without why, the doc is just commit-message restatement.

## When you can stop maintaining the document

When the bug class is closed — chkdsk runs clean, the porting effort lands, the validator stops complaining — write a final "Conclusion" section summarising:

- Total iterations to closure.
- Which fixes were independent vs which were symptoms of one root cause.
- What's still unaddressed and tracked elsewhere (link to issues).

After closure the document is read-only history. Don't append to it for unrelated subsequent work; that's a new document.

## Mantra

When tempted to skip the entry, ask: **"Six months from now, how will the next reader know why this byte is what it is?"** If the answer involves re-running the loop from scratch, the entry isn't optional.
