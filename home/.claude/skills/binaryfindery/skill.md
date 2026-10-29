# binaryfindery

Use this skill when the user provides binary files and wants to understand the format or produce a `.ksy` schema. Invoke as `/binaryfindery`.

## Invocation

User provides: a list of binary files (more = better; 5+ recommended) and a brief description of what the files are.

---

## Phase 1 — Corpus sanity check

Run `skeleton` across all files with no length specified (scans to smallest file boundary):

```json
{"op": "skeleton", "files": [...]}
```

**Interpret result:**
- If first 4–8 bytes contain at least one `constant` region → shared format confirmed, proceed.
- If entire first 64 bytes are `variable` → warn user that files may not share a common format. Ask them to confirm before continuing.
- Near-constant regions near the start suggest format variants (e.g. device families, version numbers).

---

## Phase 2 — Header mapping

1. `probe` every `constant` and `near-constant` region in the first 64 bytes.
2. Identify: magic bytes, version fields, format flags.
3. `probe` the first `variable` region to determine field type (serial number, timestamp, patient ID, etc.). Use timestamp interpretations — if `unix32le` or `unix32be` falls within 1990–2040 and matches a date visible in the filename, that's a strong hit.

---

## Phase 3 — Structure detection

Look for **TLV patterns** in the skeleton: alternating single `near-constant` bytes with small `variable` regions. This is a tag-length-value structure. When you see it:

1. `probe` the near-constant byte at each tag position across all files to identify the tag values.
2. `correlate` the 2–4 bytes immediately after each tag to determine if one of them is a length field (u8/u16 values that are small integers and match the length of the following variable region).

Look for **record structures**: variable regions with consistent stride. If a large variable block in the skeleton contains internal structure, run `skeleton` on just that region with a narrow window.

---

## Phase 4 — ksy authoring

Write findings to `formats/<name>.ksy`. Conventions:

- Use `seq` for fields at known fixed offsets from the start.
- Use a `size: N` placeholder with a `doc: unknown` comment for unresolved regions.
- Mark hypotheses with `doc: hypothesis — <reason>` until confirmed by probe.
- Confirmed fields: remove the hypothesis comment.
- Use `id` names that describe the field's meaning, not its position (e.g. `device_serial` not `field_at_0x22`).

Minimal ksy template:
```yaml
meta:
  id: <format_name>
  endian: le   # or be — confirm via probe
  file-extension: <ext>

seq:
  - id: magic
    size: 2
    doc: "constant 0x0001 across all files"
  - id: unknown_header
    size: 16
    doc: hypothesis — version or device family flags
```

---

## Phase 5 — Iteration loop

After each round of probing:
1. Update the ksy with confirmed fields.
2. Re-run `skeleton` with `offset` set to the first unresolved region to focus the next scan.
3. Repeat until either the full file is mapped or the user is satisfied.

Track findings as a running list in the conversation:
- ✓ Confirmed: offset, type, name, evidence
- ? Hypothesis: offset, candidate type, reason
- ✗ Ruled out: offset, what was tried, why discarded

---

## bf query interface

Build binaryfindery first if needed: `task build` (or `go build ./cmd/binaryfindery/`).

All operations pipe JSON to stdin, receive JSON from stdout:

```bash
echo '<json>' | ./binaryfindery query
# or equivalently:
./binaryfindery <op> [flags] file1 file2 ...
```

### skeleton
Find structural regions across a corpus. Collapses per-byte correlation into constant/variable runs.

```json
{"op": "skeleton", "files": ["f1", "f2"], "offset": "0x0", "length": 0}
```
- `length: 0` → scan to smallest file boundary
- Returns: `regions[]` with `start`, `end`, `length`, `verdict`, `bytes` (constant regions only)
- Verdicts: `constant` (same in all files), `near-constant` (≥80% same), `variable`

### correlate
Per-offset byte distribution. Use when you need detail inside a region skeleton flagged as variable.

```json
{"op": "correlate", "files": ["f1", "f2"], "offset": "0x22", "length": 32}
```
- Returns: `offsets[]` with `offset`, `values` (hex→count map), `verdict`

### probe
Interpret bytes at a specific offset as every common scalar type. Use `--compact` for multi-file queries.

```json
{"op": "probe", "files": ["f1", "f2"], "offset": "0x198B", "length": 8, "compact": true}
```
- `compact: true` → groups files by identical raw value, shows interpretations once per unique value (recommended for multi-file)
- `length` defaults to 8 (enough for u64/f64); max 64
- Interpretations: `u8/i8`, `u16/i16 le+be`, `u32/i32 le+be`, `u64/i64 le+be`, `f32/f64 le+be`, `unix32le/be` (if year 1990–2040), `str` (if printable ASCII ≥ 2 chars)

### strings
Extract printable strings (ASCII and/or UTF-16LE) with file offsets. Use after skeleton to surface human-readable fields without manual hex reading.

```json
{"op": "strings", "files": ["f1", "f2"], "offset": "0x0", "length": 0, "min_len": 4, "encodings": ["ascii", "utf16le"]}
```
- `length: 0` → scan rest of file from offset
- `encodings` defaults to both; pass `["ascii"]` or `["utf16le"]` to narrow
- Returns: per-file `matches[]` with `offset`, `encoding`, `value`, `bytes` (byte length consumed)
- Use first on the whole file to see all strings; then narrow with offset+length to explore a specific region

### hexdump
Formatted hex+ASCII dump of a region as JSON. Use in place of shelling out to `xxd` — keeps the interface consistent.

```json
{"op": "hexdump", "file": "f1", "offset": "0x56", "length": 128, "width": 16}
```
- `length` defaults to 256; `width` defaults to 16
- Returns: `lines[]` with `offset`, `hex` (space-separated), `ascii` (printable chars, `.` for non-printable)
- Useful for visual inspection of a specific region once skeleton has narrowed it down

### search
Find a byte pattern or ASCII string across a corpus with surrounding context. Use to locate all occurrences of a known magic, tag, or sentinel.

```json
{"op": "search", "files": ["f1", "f2"], "pattern": "0x0001", "context": 8}
```
- `pattern`: hex bytes as `"0x010203"`, or plain ASCII string (e.g. `"SW040"`)
- `context`: bytes of context on each side of each match (returned as hex)
- Returns: per-file `matches[]` with `offset`, `before`, `match`, `after` (all hex)
- Use to verify that a magic sequence appears exactly once at a fixed offset, or to find all instances of a tag value in TLV data

### classify
Entropy scan + compression magic detection. Use to identify encrypted, compressed, or structured regions in large files.

```json
{"op": "classify", "file": "f1", "window": 256}
```
- `window` defaults to 256 bytes; smaller = more granular
- Classes: `padding` (<1.0 bits), `structured` (1.0–5.5), `dense` (5.5–7.5), `compressed-or-encrypted` (>7.5)
- `compressed` class + `signature` field when a known compression magic is detected (zlib, gzip, lz4, xz, bzip2, zstd, zip, 7zip)
- Returns: collapsed `regions[]` — adjacent same-class windows merged

### anchor-skeleton
Find a byte pattern in each file, then run skeleton from a fixed offset relative to the end of the match. Solves the alignment problem when a structure starts at variable file offsets (e.g., after a variable-length text header).

```json
{"op": "anchor-skeleton", "files": ["f1", "f2"], "pattern": "0x0F017F7F1F", "anchor_offset": 5, "length": 256, "match_index": 0}
```
- `pattern`: hex bytes as `"0xHEX"` or ASCII string
- `anchor_offset`: bytes after the END of the match to start the skeleton window (may be negative to start before match end)
- `length`: bytes to scan from skeleton start (required, > 0)
- `match_index`: which occurrence to use (0=first, 1=second, etc.)
- Returns: `anchors[]` with per-file `match_at` and `skeleton_at`, plus `regions[]` with RELATIVE offsets (`+0x0`, `+0x1`, …)
- Use `match_index: 1` to align on the second occurrence — useful when a format stores a template record twice (header + data)
- If the pattern is not found in any file, returns `status: error`. Files where the pattern is absent are silently skipped (counted in `files` denominator).

### record
Treat a region as a flat array of fixed-stride records and report per-column byte statistics. Aggregates across multiple files.

```json
{"op": "record", "files": ["f1", "f2"], "offset": "0x18D", "length": 84, "stride": 3}
```
- `stride`: record width in bytes (required, > 0)
- `length: 0` → rest of file from offset
- Returns: `stride`, `records` (total records sampled), `files`, `columns[]`
- Each column has `position`, `samples`, `verdict` (constant/near-constant/variable), `bytes` (if constant, hex without `0x`), `values` (if variable, hex→count map)
- Use when skeleton shows a regular alternating pattern — try stride equal to the apparent period

---

## Heuristics cheat sheet

| Pattern | Likely meaning |
|---|---|
| Constant 2–4 bytes at offset 0 | Magic number / format identifier |
| Near-constant byte, rest variable | Version or device family flag |
| 16+ bytes of constant `0x00` | Padding / reserved header space |
| Variable 8–16 bytes after header | Serial number or device ID (probe as str) |
| Variable 4 bytes, unix32 hit matches filename date | Timestamp field |
| Alternating near-constant + variable | TLV structure |
| Large variable block with internal near-constant bytes | Record array |
| High entropy region (classify) | Compressed or encrypted block |
| Skeleton has `constant` + `variable` alternating at fixed period N | N-byte record array → use `record` op with stride=N |
| All files have identical structure at different absolute offsets | Variable-offset landmark → use `anchor-skeleton` on a common byte sequence |
| Large zero-padded gaps between structured regions (classify=padding) | Sparse flash/EEPROM paging |
