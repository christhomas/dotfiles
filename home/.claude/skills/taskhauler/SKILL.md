---
name: taskhauler
description: Drive the Taskhauler API (boards, columns, epics, cards, comments, service accounts). Use whenever the user asks to create, list, update, move, comment on, or delete Taskhauler boards/cards/etc., or wants to automate interaction with the Task Hauler board itself. Knows the auth flow, the endpoint shapes, the mock-card-N bridge, and the URL conventions (taskhauler.localhost/<PREFIX>/<num>).
---

# Taskhauler skill

Drive the Taskhauler REST API to create / read / update / delete the product's domain entities. This is the canonical reference for any agent that wants to act on a board.

## When to use

- User says "create a board", "add a task", "list cards", "move TH-45 to Done", "comment on TH-100", "delete that comment".
- User says "open TH-45" or "share a link to that card" → produce the URL (see [URL conventions](#url-conventions)).
- User wants to seed test data, migrate cards between boards, or run bulk operations.
- Building higher-level skills on top (triage, sprint planning, agent dispatch).

## Don't use when

- The user is just asking a question about the codebase — no API call needed.
- The user wants to *modify* the API itself (handler code, schema, etc.) — that's a code change task, not a skill invocation.
- You're running tests — use `task` commands or `vitest`/`go test` directly.

## Auth

Taskhauler is installable software — do **not** assume a URL, email, or password. The user provides them by dropping a credentials file; the skill caches a token from there.

State lives under `~/.config/taskhauler/`:

- `credentials.yaml` — **manual, ephemeral.** User (or trove) drops it in. Skill deletes it after first successful login. May only exist on disk for seconds.
- `config.yaml` — **skill-generated, persistent. chmod 600.** Everything the skill needs at runtime: `url`, `email`, `access_token`, `refresh_token`, `expires_at`. Single source of truth.
- `.gitignore` — **skill-generated, persistent.** Tripwire. If the user ever turns `~` or `~/.config` into a git repo (e.g. dotfiles), this prevents `credentials.yaml` and `config.yaml` from being tracked. Contents:
  ```
  credentials.yaml
  config.yaml
  ```

### Directory bootstrap (do this once, idempotently)

Before any auth step:

```bash
mkdir -p ~/.config/taskhauler
chmod 700 ~/.config/taskhauler
if [ ! -f ~/.config/taskhauler/.gitignore ]; then
  cat > ~/.config/taskhauler/.gitignore <<'EOF'
credentials.yaml
config.yaml
EOF
fi
```

Do not skip this — it's the only defence against an accidental `git add ~/.config/`.

### Resolution order (run this before any API call)

1. **Read config.yaml.** If missing, jump to step 4.
2. **Use cached token.** If `expires_at - 60s > now`, use `access_token`. Done.
3. **Refresh.** POST `${url}/api/v1/auth/refresh` with the `refresh_token`. On success: update `access_token`, `refresh_token`, `expires_at` in config.yaml and use the new `access_token`. On failure: fall through to step 4.
4. **Login from credentials.** Read `~/.config/taskhauler/credentials.yaml`:
   ```yaml
   url: http://taskhauler.localhost
   email: chris@teamagentica.com
   password: hunter2
   ```
   POST `${url}/api/v1/auth/login` with `email` + `password`. On success:
   - Write `~/.config/taskhauler/config.yaml` (chmod 600) with `url`, `email`, `access_token`, `refresh_token`, and `expires_at = now + access_token_ttl_seconds` (server tokens are 1h).
   - `rm ~/.config/taskhauler/credentials.yaml` — the password should not linger. Do this even if it would have expired from trove on its own; the file's purpose is over.
5. **No credentials.yaml** → stop and instruct the user:

   > Create `~/.config/taskhauler/credentials.yaml` with `url`, `email`, `password` (see template above), then re-run. The file will be deleted automatically after login.

### Trim whitespace from every YAML value

Hand-edited YAML files often pick up trailing spaces, tabs, or surrounding newlines — especially on the password line. Strip leading/trailing whitespace from **every** value read from `credentials.yaml` or `config.yaml` before using it. A bad password with a trailing space fails login with a misleading 401.

```bash
trim() { /usr/bin/sed -E 's/^[[:space:]]+|[[:space:]]+$//g'; }
URL=$(yq -r .url   "$CFG" | trim)
EMAIL=$(yq -r .email    "$CFG" | trim)
PASS=$(yq -r .password  "$CFG" | trim)
```

In Python: `value.strip()`. Apply this to URL, email, password, access_token, refresh_token, and any other scalar.

### config.yaml shape

```yaml
url: http://taskhauler.localhost
email: chris@teamagentica.com
access_token: eyJ...
refresh_token: eyJ...
expires_at: 1716223200   # unix seconds
```

### Service-account tokens (CI / headless)

Long-lived `tha_…` bearer strings. Skip the credentials flow — write `config.yaml` directly:

```yaml
url: https://taskhauler.your-domain.com
email: service-account@example
access_token: tha_xxx
refresh_token: null
expires_at: 0
```

`expires_at: 0` tells the skill to never refresh. On 401 it falls to credentials.yaml; in pure-CI you keep that file absent so failure is loud.

### Running it

The preamble at [`templates/_preamble.sh`](templates/_preamble.sh) implements the full resolution order above using only `grep`, `sed`, `jq`, `curl` (no `yq` / `PyYAML` dependency). Every other template `source`s it and gets `$URL`, `$API`, `$TOKEN`, `${H[@]}` set. Prefer the templates over open-coding curl calls — see [Templates](#templates).

## Entity reference

### Boards

```
GET    /boards                       → Board[]
POST   /boards                       body: { name, prefix?, description? }   → Board
GET    /boards/{id}                  → Board
PUT    /boards/{id}                  body: { name?, prefix?, description? }  → Board
DELETE /boards/{id}                  → 204
```

**Prefix auto-derivation.** If you POST a board with `name` but no `prefix`, the backend derives one from the name (multi-word: word initials; single-word: first 4 chars; stop words "the/a/an/of/for/and" dropped). If the derived prefix already exists, a counter is appended (`INFR`, `INFR2`, `INFR3`). To override, pass an explicit `prefix`.

**Board shape:**
```ts
{ id: string, name: string, prefix: string, description: string,
  created_at: number (millis), updated_at: number, deleted_at: null|number }
```

### Columns (nested under board)

```
GET    /boards/{id}/columns
POST   /boards/{id}/columns          body: { name, position }
PUT    /boards/{id}/columns/{cid}    body: { name?, position? }
DELETE /boards/{id}/columns/{cid}    → 204
```

Position is a `float` so you can splice columns without renumbering. Convention: positions 0/1/2/3 for new boards; subsequent inserts use midpoints (see `lib/positions.ts` in the frontend for the algorithm).

### Epics (nested under board)

```
GET    /boards/{id}/epics
POST   /boards/{id}/epics            body: { name, description?, color, position }
PUT    /boards/{id}/epics/{eid}      body: { name?, description?, color?, position? }
DELETE /boards/{id}/epics/{eid}      → 204  (cards keep their epic_id pointer, just dangle)
```

`color` is a hex string (e.g. `#5b5bd6`). Used for the EpicChip dot + swimlane left-stripe.

### Cards (nested under board, but per-card endpoints use /cards/{cid})

```
GET    /boards/{id}/cards            → Card[] (with assignee_name + status_name enriched)
GET    /boards/{id}/cards/search?q=  → Card[] (server-side LIKE on title/description/labels)
POST   /boards/{id}/cards            body: { column_id, epic_id?, title, description?, ... }
GET    /cards/{cid}                  → Card
GET    /boards/{id}/cards/number/{num}  → Card    (lookup by card.number)
PUT    /boards/{id}/cards/{cid}      body: any subset of fields
DELETE /boards/{id}/cards/{cid}      → 204
```

**Card shape (full):**
```ts
{ id: string, number: int, board_id, column_id, epic_id, title, description,
  card_type: "task"|"bug"|"", priority: "low"|"medium"|"high"|"urgent"|"",
  assignee_id: int (0=none), assignee_agent: string ("" = none),
  assignee_name: string (server-enriched, never accept on POST),
  status_name: string (server-enriched, column.name),
  labels: string (comma-separated), due_date: int|null (millis),
  position: float, created_at, updated_at, deleted_at }
```

**Move a card** = PUT with the new `column_id` (and optionally `position`).
**Reassign** = PUT with new `assignee_id` OR `assignee_agent`.
**Reschedule** = PUT with new `due_date`.

### Comments (nested under card)

```
GET    /cards/{cid}/comments              → Comment[] (with author_name enriched)
POST   /cards/{cid}/comments              body: { body }   → Comment
DELETE /cards/{cid}/comments/{cmid}       → 204
```

**Comment shape:**
```ts
{ id: string, card_id, author_id: int, author_name: string,
  body: string, created_at: number, deleted_at: null|number }
```

The author is taken from the auth token (no need to send `author_id`).

### MCP tool endpoints

The same operations are exposed under `/mcp/*` with the MCP convention (one POST per tool, request body matches the tool schema). Useful when an MCP client (Claude Code, Claude Desktop) is driving. See `GET /api/v1/mcp` for the full tool registry; 15 tools cover boards/epics/tasks/comments.

### Service accounts (admin-only)

```
GET    /service-accounts                              → User[] (is_service_account=true)
POST   /service-accounts                              body: { name, display_name } → { user, token: "tha_..." }
POST   /service-accounts/{id}/tokens                  → { token } (issue another)
DELETE /service-accounts/tokens/{token_id}            → 204 (revoke)
```

The token is shown **once** at issuance and is unrecoverable — store it immediately.

## URL conventions

The frontend uses path-based routing. URLs are shareable:

- `http://taskhauler.localhost/` → root, shows first board
- `http://taskhauler.localhost/<PREFIX>` → board with that prefix
- `http://taskhauler.localhost/<PREFIX>/<num>` → board, card #num selected

Examples:
- `http://taskhauler.localhost/TH/100` → opens the Task Hauler board, selects TH-100
- `http://taskhauler.localhost/V2/45` → opens the V2 board, selects V2-45

The trailing segment is parsed loosely — `/TH/100` and `/TH/TH-100` both work (regex extracts the digits).

When the user asks to "open" or "share" a specific card, produce the URL using the board's `prefix` field + the card's `number` field.

## Templates

The `templates/` directory contains ready-to-run shell scripts for the most common operations. Each one `source`s `_preamble.sh` (auth + sets `$URL`, `$API`, `$TOKEN`, `${H[@]}`) and emits results as TSV (with a markdown table where useful).

**Prefer running a template over open-coding curl.** Templates handle prefix→board-id resolution, column-name→column-id resolution, the auth dance, and error cases. If a needed operation has no template yet, add one — they're cheap and consolidate the right idioms.

| Template | Operation |
|---|---|
| [`_preamble.sh`](templates/_preamble.sh) | Sourced by all other templates. Handles auth, sets `$URL` / `$API` / `$TOKEN` / `${H[@]}`. |
| [`boards-list.sh`](templates/boards-list.sh) | List boards with prefix, name, card count. |
| [`boards-create.sh`](templates/boards-create.sh) | `<name> [prefix] [description]` — create a board (backend derives prefix if omitted). |
| [`columns-list.sh`](templates/columns-list.sh) | `<board>` — list columns (position, name, id). |
| [`epics-list.sh`](templates/epics-list.sh) | `<board>` — list epics (position, name, color, id). |
| [`cards-list.sh`](templates/cards-list.sh) | `<board>` — list cards (number, title, status, priority, assignee). |
| [`cards-search.sh`](templates/cards-search.sh) | `<board> <query>` — server-side LIKE on title/description/labels. |
| [`cards-get-by-ref.sh`](templates/cards-get-by-ref.sh) | `TH-100` → full card JSON. |
| [`cards-create.sh`](templates/cards-create.sh) | `<board> <column-name> <title> [description]` → created card. |
| [`cards-move.sh`](templates/cards-move.sh) | `<card-ref> <target-column-name>` → updated card. |
| [`comments-add.sh`](templates/comments-add.sh) | `<card-ref>` + body on stdin → multi-line safe + read-back verified. |
| [`url-build.sh`](templates/url-build.sh) | `TH-100` → shareable card URL. |
| [`service-accounts-list.sh`](templates/service-accounts-list.sh) | List service accounts (admin only). |

**Board references** in any template that takes `<board>` accept either a prefix (`TH`) or a UUID. **Column names** are matched case-insensitively. **Card refs** (`TH-100`) work everywhere; the template parses prefix + number.

### When the user requests something without a template

1. Check the [Entity reference](#entity-reference) section for the endpoint + shape.
2. Write a one-off using the same idiom as the closest existing template (source `_preamble.sh`, use `${H[@]}`).
3. If the operation will recur, save it as a new template under `templates/` and add a row above.

## Mock-card-N bridge (frontend-specific)

The frontend's `src/mock/` files reference cards by placeholder strings like `mock-card-1`, `mock-card-2`, etc. These are resolved at render time to the Nth real card sorted by `number`. If you're writing skill code that touches the mock-data layer, use the resolver in `frontend/src/components/board/rail/CardDetailPanel.tsx` (or copy it).

When the corresponding real API endpoints exist (TH-76 activity feed, TH-80 suggestions, etc.), this bridge gets removed and consumers read real `card_id`s.

## Multi-line bodies (descriptions, comments)

[`comments-add.sh`](templates/comments-add.sh) is the canonical pattern: body comes in on stdin, gets JSON-encoded via `jq -n --arg`, and is read back to verify byte-equal landing.

If you're writing ad-hoc bash without the template: never construct JSON by string-concat for multi-line bodies. Either pipe the body through `jq -n --arg b "$BODY" '{body:$b}'` (works for moderate sizes) or write to a file and use `jq -n --rawfile b /tmp/body.txt '{body:$b}'` for arbitrary content.

## Error handling

Every endpoint returns a JSON error body on 4xx/5xx:

```json
{ "error": "human-readable message" }
```

The most common errors:

- **401** — token expired or missing. Re-run login.
- **403** — endpoint requires admin (service-accounts/*).
- **404** — entity not found (wrong id, soft-deleted, etc.).
- **400** — request body validation failed; the `error` message names the field.
- **500** — server error; usually a constraint violation. Common one: trying to create a second board with an empty/duplicate prefix → that's [TH-20](http://taskhauler.localhost/TH/20) but only on legacy schema.

`curl -sf` exits non-zero on 4xx/5xx — use that for error handling. For more detail, drop the `-f` and inspect the body.

## Don't

- **Don't commit any of `~/.config/taskhauler/*` to a repo.** The token file is allowed on disk (chmod 600) but is per-machine and per-user. `credentials.yaml` is doubly off-limits — it carries the password — and the skill deletes it after login anyway.
- **Don't `INSERT` into the database directly.** Use the API so events (TH-17) fire and triggers run. If you absolutely must (e.g. migration), use `task psql` and document why in a comment.
- **Don't bypass the prefix derivation when bulk-creating boards** — let the backend pick. Only override with `prefix` when you specifically need a non-default value, and remember the unique-after-trim-uppercase rule.
- **Don't construct JSON by string concatenation in bash.** Use `jq -n --arg` (single-line) or Python (multi-line) — escaping bugs are silent and hard to debug.
- **Don't assume a column named "Done" exists.** Always list columns and either match by name (case-insensitive) or by an explicit `done_column_id` configured elsewhere.

## Anchors

- Backend source: `backend/internal/handlers/handlers.go`, `internal/auth/`, `internal/storage/`
- OpenAPI spec: `backend/openapi.json` (37 paths, 95 schemas)
- Frontend API client: `frontend/src/api/client.ts` (TypeScript reference impl)
- Task Hauler board id: `aa4c87b6-bde7-4394-9db5-f59325e3aca0` (prefix `TH`)
- Repo: https://github.com/antimatter-studios/taskhauler
