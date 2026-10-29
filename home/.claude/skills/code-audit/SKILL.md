---
name: code-audit
description: License & IP audit. Inventories every package, dependency, vendored source, and bundled binary in a project (or a specific subset), classifies each by license, and flags copyleft contamination, copied/linked third-party source, and unattributed material. Outputs a structured report to `docs/ip-audit-<YYYY-MM-DD>.md` of the analyzed project. Use before adding a vendor crate, before publishing/distributing, after a significant change set, or when a user asks for a "license audit", "IP audit", "GPL check", or "code audit".
user-invocable: true
---

# Code Audit (License / IP)

Produces a defensible record of *every* third-party-licensed bit of code in a project: declared licenses, transitive deps, vendored sources, copied snippets, and bundled binaries — plus an explicit "we did NOT use X" list for known risky source material in the same domain.

The audit is **internal** by default. Some sections (notably the "deliberately avoided" list) name competitor or copyleft projects and should not be published verbatim — flag this in the report header.

## When to invoke

Run the skill when any of the following is true:

- A new vendor crate / package / module has been added.
- A new direct dependency has been added (especially: compression, encryption, filesystem, networking, crypto — the main copyleft-leak surfaces).
- Code is being prepared for distribution (binary release, App Store submission, crates.io publish, npm publish, container image push).
- The user asks for a "license audit", "IP audit", "GPL check", "code audit", or similar.
- A significant batch of work just landed (e.g., autonomous overnight run, large feature merge).
- A re-audit trigger from a previous report has fired.

If the user names a specific scope ("audit the four image drivers", "audit just the new vendor dirs"), respect that scope. Otherwise audit the whole project tree.

## The legal model the skill operates under

This is the framing every check below derives from. Get this right or the whole audit is wrong.

**Copyleft contamination is triggered by:**
1. **Copying** copyleft-licensed source into our tree (verbatim, paraphrased, or "inspired by" at the line level).
2. **Linking** copyleft-licensed code into our binary — static or dynamic — at build time, including `cargo` deps, `npm` deps, `go.mod` deps, vendored `.a`/`.so`/`.dylib` artifacts, and FFI shims that pull in copyleft objects.

**Copyleft contamination is NOT triggered by:**
3. **Invoking** a copyleft-licensed program at arm's length via fork/exec from a CI script, test harness, build tool, or developer machine. The FSF treats this as separate-process invocation. (Every proprietary product built on Linux uses gcc/bash/make this way.)

The skill enforces the distinction precisely. (1) and (2) are violations; (3) is fine.

**Separate from copyleft — the "no hardcoded tool names" rule.** Many projects forbid encoding specific third-party tool/project names in their source, comments, CI workflows, or docs. There are two distinct reasons a project may want this, and both can apply at once:

1. **Clean-room legal posture / no volunteered foothold for accusation.** Naming a copyleft prior-art project in our tree creates a paper trail an opposing party could cite as evidence we "consulted" that project. The deeper point: IP law is **asymmetric** — defending a baseless accusation is still expensive (often 6–7 figures), so the goal isn't only "preserve clean-room defense in court," it's "don't volunteer connections that can be weaponized against us in the first place." Mentioning a project's name hands a plaintiff a free foothold to allege copying that they would otherwise have had to prove on their own. The implementation may be entirely clean, but the textual reference alone gives an accusation somewhere to land. Generic phrasing ("a tool that checks the disk images", "a Linux validator") preserves the defense and preempts the accusation; specific names ("qemu-nbd", "ntfs-3g", "mkntfs") create the foothold. Applies primarily to copyleft prior art in the same problem domain as our implementation, but the principle generalises to any project we'd rather not be accused of copying.

2. **Loose coupling / no hardcoded tool identity.** Standard software-engineering hygiene: encoding a specific project name turns a swappable dependency into a hardcoded one. "Use the configured disk-image validator" survives a tool swap; "use qemu-nbd" doesn't. Applies to *any* tool, copyleft or not — same principle that says don't hardcode `xcode-15.4` or `python-3.11` in build scripts. Reference tools by their **role** in the workflow, not by proper name.

Both reasons reinforce the same rule: **prefer category nouns over project names in source/comments/CI/docs**. Check the project's CLAUDE.md and memory for any such policy and apply it on top of the license-risk audit. The audit report should call out hardcoded tool-name occurrences as a separate finding category from copyleft contamination.

Permitted patterns when a tool must be invoked from a committed file:
- Reference via a generic env var (`$VALIDATOR`, `$IMAGE_CHECKER`).
- Use a wrapper script with a generic name (`check-image.sh`) that internally calls the specific tool.
- Keep the invocation in a developer-local uncommitted script.

The audit checks for violations of this rule independently of whether the named tool is copyleft — a hardcoded *permissive* tool name is also a coupling smell, even if not a legal one.

## Risk taxonomy

| Status | Meaning | Action |
|---|---|---|
| ✅ **Clean** | Permissive license (MIT, Apache-2.0, BSD-2/3, ISC, Zlib, 0BSD, Unlicense, CC0, MPL-2.0-file-level). | Note in report. |
| ⚠️ **Attribution-required** | MIT/Apache/BSD — requires shipping the LICENSE file. | Note in report; verify LICENSE files are bundled in distribution. |
| ⚠️ **Weak copyleft** | LGPL, MPL-2.0-at-distribution. Dynamic linking permitted under conditions; static linking restricted. | Flag for review; document linkage model. |
| ❌ **Strong copyleft** | GPL-2.0, GPL-3.0, AGPL, EUPL. Linking infects our license. | Block; redesign or remove. |
| ❌ **Unlicensed / unclear** | No LICENSE file, "All rights reserved", non-standard license. | Block until clarified. |
| 🚫 **Source-available / non-OSS** | BSL, SSPL, Elastic License, Commons Clause. | Block until commercial terms confirmed. |
| 📋 **CLI-tool-only** | Copyleft program invoked via fork/exec from CI / build / test only — not linked, not copied. | Permitted. Document the invocation. Apply project naming policy if any. |

## Audit methodology

Run the steps in order. Don't skip — each step finds a different class of leak.

### Step 1 — Establish scope

- Determine the project root (the directory containing the top-level VCS root, manifest file, or the path the user named).
- If the user named a subset (specific crates, vendor dirs, recent changes), honor it. Otherwise: full project.
- Read any project-level policy:
  - `CLAUDE.md` at every level
  - `~/.claude/projects/<project-slug>/memory/MEMORY.md` and any `feedback_no_*` or `feedback_*license*` files
  - Existing `docs/ip-audit-*.md` (if present, this audit is a re-audit — diff against it)
- Note any project-specific forbidden-name policy (tool/competitor names that must not appear in shipped artifacts).

### Step 2 — Per-package license declarations

For every package manifest in scope, read and record:
- Declared license string (`license` field in Cargo.toml / package.json / pyproject.toml / etc.)
- Copyright line from `LICENSE` / `LICENSE.md` / `COPYING`
- Repository URL (helps verify ownership)

Per ecosystem:

| Ecosystem | Manifest | License field |
|---|---|---|
| Rust | `Cargo.toml` | `[package].license` or `license-file` |
| Node/JS/TS | `package.json` | `license` |
| Go | `go.mod` + per-dep `LICENSE` | (no field; inspect `LICENSE` of each dep) |
| Python | `pyproject.toml` / `setup.py` | `license` / `License ::` classifier |
| Swift SwiftPM | `Package.swift` | (no field; inspect target sources for LICENSE) |
| Swift Xcode | `*.xcodeproj` packaged frameworks | per-framework `LICENSE` |
| C/C++ CMake | `CMakeLists.txt` + LICENSE files | manual |
| Ruby | `Gemfile` + `*.gemspec` | `spec.license` |

Flag any package missing a license declaration or LICENSE file.

### Step 3 — Direct dependencies

For each in-scope package, list direct dependencies and their licenses. **Use the build tool's resolution, not just the manifest** — manifests can have wildcards, build tools resolve to specific versions.

| Ecosystem | Command |
|---|---|
| Rust | `cargo metadata --format-version 1` (parse `packages[].license`) or `cargo tree --prefix none --no-dedupe` + lookup |
| Node | `npm ls --json` / `pnpm licenses list` |
| Go | `go list -m -json all` then read each module's `LICENSE` |
| Python | `pip-licenses --format=json` (in the project venv) |
| Swift | parse `Package.resolved` then fetch each repo's LICENSE |

Look up each dep's license in its registry (crates.io, npm, PyPI) or its repo's LICENSE file when the registry doesn't carry the field.

### Step 4 — Transitive dependency tree

Same tools, recurse fully. Catch the cases where a permissive direct dep pulls in a copyleft transitive. Common offenders to watch for: GMP (LGPL, often via crypto), readline (GPL, via REPL libs), GNU bison output (used to be infectious; resolved in 2007 but historic claim still surfaces), MySQL client libs (GPL), libvncserver (GPL).

Output: a single table — every distinct `(crate, version)` with license. No duplicates beyond what version-divergence demands.

### Step 5 — Vendored / bundled source

Scan for source code physically inside the project tree that came from a third party:

- Common dirs: `vendor/`, `third_party/`, `external/`, `Sources/Vendor/`, `submodules/`, `node_modules/` (usually gitignored — ignore unless committed), `Sources/Frameworks/`.
- Git submodules: `git submodule status` — record each submodule's license.
- Worktree-vendored files: any `.c`/`.cpp`/`.rs`/`.go`/`.swift`/`.py`/`.js`/`.ts`/`.h` with a third-party copyright header. Grep for `Copyright` in source headers excluding our own copyright string.
- File-level license markers: `SPDX-License-Identifier:` headers — collect distinct values.

For each found item, classify per the risk taxonomy.

### Step 6 — Bundled binaries

Binary blobs are the easiest leak to miss:

- `.a`, `.so`, `.dylib`, `.dll`, `.lib`, `.framework/` directories
- Pre-compiled `.o` / object archives
- Docker base images referenced in `Dockerfile`
- Embedded firmware blobs

For each: identify the source project and license. Linking a GPL `.a` is a copyleft event even if no source is in the tree.

### Step 7 — Source-of-design analysis

For any code that implements a third-party-defined format / protocol / algorithm — even when written from scratch — record the **specification source** that was followed:

- Spec document name, publisher, URL, year
- License of the **document** itself (this is separate from any reference implementation's license)
- Whether implementation is **independent** (clean-room from spec) or **derived** (from a reference implementation's source)

Format definitions are not copyrightable in most jurisdictions; specific creative implementations are. Independent implementation from a published spec is well-established as non-infringing even when a reference implementation exists under copyleft.

If the only available "spec" is reverse-engineered from a copyleft reference implementation: that is **derivation**, not clean-room. Flag it.

### Step 8 — Verified-absent check

For each format/protocol/algorithm covered, list the *known reference implementations in the wild* (especially copyleft ones) and explicitly confirm none were consulted. Examples:

- Filesystem driver implementing ext4 → did NOT consult `linux/fs/ext4/*.c` (GPL-2.0).
- Disk-image reader implementing qcow2 → did NOT consult `qemu/block/qcow2*.c` (GPL-2.0+).
- NTFS implementation → did NOT consult ntfs-3g (GPL-2.0+) or any commercial NTFS implementation.

This is the section future auditors and lawyers care most about. Be specific. Vague "no GPL code copied" is not enough — name the specific source trees that were avoided.

### Step 9 — CLI-tool-only invocations

Per the legal model in §"The legal model": copyleft tools invoked at arm's length from CI scripts, build tooling, or test harnesses are permitted. Inventory them anyway:

- `Makefile` / `build.rs` / `package.json` scripts / `.github/workflows/*.yml`
- Test harness shell-outs: `Command::new("...")`, `subprocess.run(["..."])`, `child_process.spawn(...)`

For each: name the tool, name its license, confirm it is invoked separately (not linked / not source-copied), and whether the project's naming policy permits referencing it in shipped artifacts.

### Step 10 — Apply project naming policy

If the project memory or CLAUDE.md declares a naming policy (e.g., "never mention X, Y, Z in code/CI/docs"):

- Grep the entire repo for the forbidden names.
- Exclude `.git/`, build artifacts, this audit doc itself, and any explicitly-internal docs (READMEs / commit messages / public docs only).
- Report violations as a separate section.

This is **separate from license risk** — it's a project-specific perception/branding rule that lives next to the IP audit because the same audit pass catches it.

### Step 11 — Render the report

Write to `<project_root>/docs/ip-audit-<YYYY-MM-DD>.md` using the structure in the next section. If the file already exists for today's date, suffix with `-2`, `-3`, etc. — never overwrite.

## Report structure

```markdown
# IP & License Audit — <YYYY-MM-DD>

[One-paragraph summary: what was audited, the high-level verdict, and
any items that need follow-up.]

**This document is internal.** [If a forbidden-name policy applies:]
It names third-party projects that the project policy forbids
mentioning in shipped artifacts; do not publish verbatim.

## Summary

✅ / ⚠️ / ❌ [bullet list of top-level findings — one line each]

## Per-artifact audit

### `<path/to/artifact>`

- **License:** [declared license + copyright line]
- **Direct deps:** [list with licenses]
- **Source of design:** [spec / original / derived — with citation]
- **Verified absent:** [explicit list of reference implementations
  that were NOT consulted]
- **Bundled binaries / vendored source:** [list, or "none"]
- **CLI-tool-only invocations:** [list, or "none"]
- **Risk:** [None / Low / Medium / High] — [reason]

[Repeat for every artifact in scope.]

## Transitive dependency tree

| Crate / Package | Version | License | Direct? |
|---|---|---|---|
| ... | ... | ... | ... |

**Verdict:** [permissive-only / contains weak copyleft / contains
strong copyleft / contains unlicensed]

## What was deliberately NOT used

[Bulleted list of reference implementations / source trees
considered and explicitly avoided. Be specific — name projects.
This list lives in this internal document only.]

## Spec sources cited

| Format / Protocol | Document | Origin | Document license | Used as |
|---|---|---|---|---|
| ... | ... | ... | ... | clean-room / derived |

## Hardcoded tool-name compliance

[For each forbidden / discouraged name, list grep findings.]

| Name | Reason (clean-room / coupling / both) | Files where it appears | Action |
|---|---|---|---|
| ... | ... | ... | rename to generic / move to local script / keep with justification |

✅ / ❌ status per name. Note that a hardcoded *permissive* tool name is still a coupling smell even when not a legal one.

## CLI-tool-only invocations (permitted)

| Tool | License | Invoked from | Linked? | Named in shipped artifacts? |
|---|---|---|---|---|
| ... | ... | ... | No | No / Yes (acceptable per policy) |

## Audit conclusions

1. **Distribution under <license>:** [safe / blocked / conditional]
2. **Bundling with <product>:** [safe / blocked / conditional]
3. **Publishing to <registry>:** [safe / blocked / conditional]
4. **Commercial sale:** [unrestricted / restricted by X]
5. [Other distribution-shape conclusions specific to the project]

## Re-audit triggers

This audit must be re-run if any of the following land:

- A new vendor crate / package / submodule is added.
- A new direct dependency is added (especially: <high-leak-categories>).
- Any code is copied verbatim from a third-party project.
- A new format/protocol implementation lands without a clean-room
  spec source.
- Any of: [project-specific triggers]

## Diff vs previous audit

[If a prior `docs/ip-audit-*.md` exists:]
- Added: [new artifacts / deps]
- Removed: [artifacts / deps no longer in tree]
- Changed: [version bumps with license changes]
```

## Handling re-audits

If a previous audit exists at `docs/ip-audit-*.md`:

1. Read the most recent prior audit.
2. Diff the dependency tree, vendored sources, and bundled binaries.
3. Focus the new audit on what *changed* — but still re-emit the full transitive tree (versions drift, transitives can flip license).
4. Include a "Diff vs previous audit" section listing additions / removals / version-bump license changes.
5. The re-audit triggers from the prior doc become part of this audit's input — verify each one was honored.

## Honesty rules

- **No "verified absent" without verification.** If you didn't actually grep for a name or read a file, don't claim it's absent. Say "not checked" or do the check.
- **No claim of clean-room without a spec citation.** Independent implementation must cite the spec it followed. "Derived from internal knowledge" is not a citation.
- **No copy-paste from a prior audit's verdicts** without re-running the underlying check. Versions drift and transitives flip.
- **Surface unknowns.** If a dep's license is unclear, the report says so. Don't guess.
- **Don't speculate on legal interpretation beyond the model in §"The legal model".** If something falls outside that model (patent claims, trademark, contributor licensing, dual-license election, region-specific quirks), flag it for legal review and stop — this skill does license/IP-source review, not legal counsel.

## Final deliverable

A single markdown file at `<project_root>/docs/ip-audit-<YYYY-MM-DD>.md`.

Print the path to the file at the end of the run, plus a one-line verdict (✅ clean / ⚠️ items to review / ❌ blocking issues found).
