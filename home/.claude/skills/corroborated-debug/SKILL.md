---
name: corroborated-debug
description: Evidence-driven debugging when the error is generic and the cost of guessing is high. Use when a black-box validator (chkdsk, fsck, regulator, formal checker, fuzzer) reports "X is wrong" without saying which byte/line/field; when porting code with subtle behaviour differences; when a reference implementation exists that you can compare against; or whenever you'd otherwise be tempted to "try this and see if it fixes it." Composes with dev-loop — operates inside its Implement phase to make each change provable rather than speculative.
---

# Corroborated Debugging

## File-edit collision guard (mandatory)

You may run alongside other writers (a teammate Claude, a hook, the user). Before editing any **existing** file:

1. **On read** — record the file's content hash (`shasum -a 256 <file>`) as your baseline.
2. **Before you write** — recompute the on-disk hash; proceed only if it still matches.
3. **If it differs** — someone changed the file since you read it. **Do NOT overwrite.** Re-read, then make a *smaller, surgical* `Edit` touching only your region and preserving their change. Never overwrite a changed file with your stale buffer.
4. **Prefer `Edit` over `Write`** for existing files; reserve `Write` for brand-new files.
5. **Never delete a test** (or any file) without explicit user confirmation.

(Same contract as the dev-loop skill this composes with — it closes the lost-update race.)

A debugging methodology that forces every code change to be backed by **evidence**, not plausibility. Designed for the case where:

- The validator/test gives generic errors ("structure is corrupt", "attribute X is wrong") without identifying the specific field.
- A reference implementation exists that you can produce parallel output from.
- Public documentation describes the format/protocol/behaviour.
- The cost of a wrong guess is high (long CI cycle, real hardware, irreversible state, customer impact).
- You catch yourself reasoning "this is *probably* the issue."

The protocol exists because the alternative — guess, change, re-run, repeat — burns iterations and leaves the codebase littered with speculative changes that may or may not have helped, with no way to tell which.

## The protocol

**Don't change code from plausibility. Change code from a byte-diff.**

Every change must answer three questions, in this order:

1. **What is observably different?** A diff of bytes / lines / values between our output and a known-good reference. Not "I think field X might be wrong" — *show* that field X differs and by how much.
2. **What does the public spec say that field means?** Microsoft/IETF/POSIX/etc. documentation, never reverse-engineered competitor source. The spec tells us *why* the field matters.
3. **What is the minimal change to align our output with the reference, in the way the spec mandates?** Cite both the diff and the spec in the commit message and a code comment.

If you can't answer all three, you don't have a fix. You have a hypothesis. Convert the hypothesis to evidence (gather more diff data) before changing code.

## Phases

### Phase 1: Reproduce + capture

Get the failing scenario into a tight loop you control. If it currently runs in CI on push, find a local equivalent — VM, container, on-host runner — even if it takes a few hours of setup. CI cycles of >2 minutes per iteration will dominate the total time spent on the bug; a one-time setup investment usually pays back within the first few hours.

For each run, capture *every* artifact you can:

- The error output verbatim (don't paraphrase — exact wording matters for grep).
- The output we produced (file, bytes, response).
- The output the reference produced (run alongside, same inputs).
- Any side-channel data: event logs, syscall traces, structured telemetry.

Store them in a `diag/` directory keyed by iteration number. Compare across iterations; patterns that survive multiple runs are real bugs, transient ones are environmental.

### Phase 2: Build the corroboration mechanism

Before you change any production code, build the diff harness. Concretely, this almost always means:

1. **Run a reference implementation alongside ours** with the same inputs. Microsoft's `format.com`, glibc, the kernel's reference test suite, an old known-good release, a competitor's open-source tool — anything that produces the format we're trying to produce, that you trust to be correct.
2. **Dump structured fields from both outputs.** Don't rely on naked hex; parse the format and label each field. "rec 6 `$FILE_NAME` `indexed_flag` byte" beats "byte at offset 0x158".
3. **Print them side by side** in a table the user can read at a glance. Tables make differences pop visually; long unstructured hex hides them.

When the harness is good, the bug usually leaps out of the table and you stop arguing about hypotheses.

This is the highest-leverage step in the whole protocol. If you skip it and proceed by hypothesis, you will burn iterations.

### Phase 3: Identify the actual difference

Read the diff. Don't editorialise. Just enumerate which fields differ and by how much.

For each difference, classify it:

- **Layout choice** — both values are valid per spec; reference and ours just made different choices (volume size, MFT position, random GUID, timestamp). **Not a bug**, leave alone.
- **Provably wrong against spec** — one of the two values violates a documented rule. The reference is by assumption correct; therefore ours is the bug.
- **Inconsistency within our own output** — two fields that *we* wrote disagree with each other (e.g. `bytes_used` doesn't match cursor position). Spec violation by us regardless of the reference.

Only categories 2 and 3 justify code changes.

### Phase 4: Cite the public spec

For every change, find the publicly published documentation that describes the field. Quote enough of it in the commit message that a reviewer can understand the change without re-discovering the spec themselves.

**Hard rule: never consult licence-incompatible sources.** Reverse-engineered GPL implementations of proprietary formats (e.g. NTFS-on-Linux tools), competitor source under any copyleft licence, leaked specs — these can taint clean-room work. Stick to: vendor-published specs, IETF RFCs, published books, public conference talks. If a project has a memory file or repo-level rule about specific names that must not appear in code/comments/CI, that rule supersedes everything else here — read CLAUDE.md and the user's auto-memory before quoting any source.

If you can't find a public source for a field's meaning, prefer "we observed reference does X; chkdsk reports Y when we don't" as the citation. That's still evidence, just observational rather than documentary.

### Phase 5: Minimal change with evidence in the commit

The change should:

- Touch the smallest possible number of lines.
- Have a code comment near the change citing the byte-diff and the spec.
- Have a commit message that includes the per-field diff table (or a representative slice of it) and links to the iteration that produced it.

The next person who reads this code in 6 months should be able to see exactly *why* this byte was set this way without needing to re-run the whole pipeline.

### Phase 6: Verify the change worked, then identify what's next

After the change, re-run and capture again. Check three things:

1. The specific error you targeted is gone.
2. No previously-passing checks regressed (this is dev-loop's territory — let its Phase 5 contract carry the load).
3. The diff table is one row shorter (or shows a different next-error).

If the targeted error is gone but a *new* error appeared, that's progress, not regression. The protocol says: capture again, diff again, fix the next one. Resist the urge to fix the new error speculatively in the same change.

## Anti-patterns

The following are forbidden under this protocol and indicate you should re-read Phase 2:

- **"Let me try this and see"** — running the pipeline to test a hypothesis, instead of running the diff harness to gather evidence. The pipeline is for verifying fixes, not generating them.
- **Bundling speculative changes** — "I'll change indexed_flag *and* the namespace *and* the MFT placement, then run." When something fixes the symptom you don't know which change did it; when it doesn't you've lost three hypotheses at once.
- **Reasoning from pattern matching to other formats** — "in FAT this field is X so probably in NTFS it's similar." Spec or it didn't happen.
- **Asserting confidence without citation** — "the indexed_flag should be 1 because it's referenced from an index." Maybe; show the diff first.
- **Re-running the validator hoping the answer changes** — same input, same output. Use the time to instrument instead.
- **Editing tests to match buggy code** — dev-loop already covers this, repeated here because under stress it's tempting.
- **Saying "this is probably the cause"** in user-facing text — convert "probably" to "the diff shows X differs from Y at offset Z, the spec says Z means W" or stop.

## Parallel hypothesis testing

When the diff surfaces multiple independent differences, you can sometimes test fixes in parallel:

- Each fix gets its own git worktree (Agent + `isolation: "worktree"`).
- Each Agent applies one fix, runs the local diff harness, returns its iteration-N artifact.
- Main thread merges only the fixes whose artifact shows the targeted error gone *and* no new errors introduced.

This is only safe when the differences are demonstrably independent (different fields, different records, different files). Two changes to the same MFT record's attribute layout are *not* independent; serialise those.

Per-fix per-Agent costs about the same wall-time as one fix, so there's no point parallelising fewer than 3 hypotheses.

## Composes with `dev-loop`

`dev-loop` enforces "tests passing before must still pass after." `corroborated-debug` enforces "code changes must come from evidence." They're orthogonal:

- Run `dev-loop` Phase 0–2 normally to establish baseline.
- When inside Phase 4 (Implement) you encounter the kind of generic / opaque error this skill is designed for, switch to corroborated-debug Phases 1–6 to produce the actual code change.
- Hand back to `dev-loop` Phase 5 onwards to verify the fix didn't regress anything.
- The artifact this skill produces (`docs/<area>-findings.md` — see below) feeds dev-loop's Phase 9 summary so iteration history is preserved.

## Findings document

Each project that uses this skill should keep a single `docs/<area>-findings.md` (or equivalent path) that:

- Logs each iteration: symptom, diff evidence, fix, result.
- Has a header explaining the corroboration mechanism (so a reader knows what artifact to look at).
- Lists "what we learned" — generalisable lessons that should inform similar work elsewhere.

This file is part of the deliverable. It's how the methodology survives across sessions and contributors. When the work is done, the document is the proof that every change was justified.

A good template:

```markdown
# <area> findings — what <validator> taught us

## How we corroborate fixes
<mechanism — e.g. "CI step formats reference + dumps both side-by-side">
<artifacts — file paths>

## Iteration log

### iter<N>: <one-line summary>

Symptom: <verbatim error>

Diagnostic: <what we ran, what data we captured>

Per-field diff:
| Field | ref | ours | spec ref |
|-------|-----|------|----------|
| ...   | ... | ...  | ...      |

Root cause: <which categorisation from Phase 3>

Fix: <minimal change description, link to commit>

Result: <error gone? new error? same error?>

## What we learned
<generalisable lessons>
```

## Mantra

When stuck, repeat: **"What does the diff say?"** If you don't have a diff, go build one. If you have a diff, the answer is in it.
