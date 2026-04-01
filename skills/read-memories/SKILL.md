---
name: read-memories
description: >
  Search past Codex or Claude Code session logs to recover your own context.
  Invoke this proactively when you need to recall past decisions, patterns,
  or unresolved work — either across all projects or scoped to the current one.
argument-hint: <keyword> [--here]
allowed-tools: Bash
---

Use this to recover your own context from past sessions. Do NOT narrate the
process to the user — silently run the query, absorb the results, and continue
with enriched context.

`$0` is the keyword to search for.
Pass `--here` as a second argument (`$1`) to scope the search to the current project only.

## Step 1 — Discover available log sources and project scope

```bash
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
WORKTREE_ROOTS="$PROJECT_ROOT"
if git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  while IFS= read -r root; do
    WORKTREE_ROOTS="${WORKTREE_ROOTS}"$'\n'"$root"
  done < <(git -C "$PROJECT_ROOT" worktree list --porcelain 2>/dev/null | awk '/^worktree / {print substr($0, 10)}')
fi
WORKTREE_ROOTS="$(printf '%s\n' "$WORKTREE_ROOTS" | awk 'NF && !seen[$0]++')"
HAS_CODEX=0
HAS_CLAUDE=0
find "$HOME/.codex/sessions" -type f -name '*.jsonl' -print -quit 2>/dev/null | grep -q . && HAS_CODEX=1
find "$HOME/.claude/projects" -type f -name '*.jsonl' -print -quit 2>/dev/null | grep -q . && HAS_CLAUDE=1

if [ -z "${0:-}" ]; then
  echo "ERROR: read-memories requires a non-empty keyword." >&2
  exit 1
fi

escape_sql_literal() {
  printf '%s' "$1" | sed "s/'/''/g"
}

KEYWORD_SQL="$(escape_sql_literal "$0")"
HOME_SQL="$(escape_sql_literal "$HOME")"

CODEX_SCOPE_PREDICATE="1=1"
CLAUDE_SCOPE_PREDICATE="1=1"
if [ "$1" = "--here" ]; then
  CODEX_SCOPE_PREDICATE=""
  CLAUDE_SCOPE_PREDICATE=""
  while IFS= read -r root; do
    [ -z "$root" ] && continue
    ROOT_SQL="$(escape_sql_literal "$root")"
    CLAUDE_ID="$(echo "$root" | sed 's|[/_]|-|g')"
    CLAUDE_ID_SQL="$(escape_sql_literal "$CLAUDE_ID")"
    CODEX_SCOPE_PREDICATE="${CODEX_SCOPE_PREDICATE:+$CODEX_SCOPE_PREDICATE OR }(project = '$ROOT_SQL' OR starts_with(project, '$ROOT_SQL' || '/'))"
    CLAUDE_SCOPE_PREDICATE="${CLAUDE_SCOPE_PREDICATE:+$CLAUDE_SCOPE_PREDICATE OR }(project = '$CLAUDE_ID_SQL')"
  done <<EOF
$WORKTREE_ROOTS
EOF
fi
```

- If both `HAS_CODEX` and `HAS_CLAUDE` are `0`, tell the user no session logs were found and stop.
- If `$0` is empty, tell the user `read-memories` requires a non-empty keyword and stop.
- If `$1` is `--here`, keep Codex results scoped to `PROJECT_ROOT`, sibling worktrees in the same repository, and descendant directories of those roots.
- For Claude Code, scope `--here` to exact project-root and sibling-worktree slugs only. Claude stores a lossy slugged project id, so descendant-directory matching is not reliable there.
- If both sources are available, prefer the current client when it clearly answers the question; otherwise search both and merge the findings mentally.
- If `HAS_CODEX` is `1`, run Step 2. Otherwise skip directly to Step 3.
- If `HAS_CLAUDE` is `1`, run Step 3. Otherwise skip it.

## Step 2 — Query Codex sessions (preview first, if available)

```bash
duckdb :memory: -c "
WITH raw AS (
  SELECT filename, timestamp, type, payload
  FROM read_ndjson('${HOME_SQL}/.codex/sessions/*/*/*/*.jsonl', auto_detect=true, ignore_errors=true, filename=true)
),
meta AS (
  SELECT filename, json_extract_string(payload, '$.cwd') AS project
  FROM raw
  WHERE type = 'session_meta'
),
messages AS (
  SELECT
    filename,
    COALESCE(meta.project, '(unknown)') AS project,
    strftime(raw.timestamp::TIMESTAMPTZ, '%Y-%m-%d %H:%M') AS ts,
    json_extract_string(raw.payload, '$.role') AS role,
    string_agg(json_extract_string(chunk.value, '$.text'), '' ORDER BY CAST(chunk.key AS INTEGER)) AS content
  FROM raw
  LEFT JOIN meta USING (filename)
  CROSS JOIN json_each(raw.payload, '$.content') AS chunk
  WHERE raw.type = 'response_item'
    AND json_extract_string(raw.payload, '$.role') IN ('user', 'assistant')
    AND json_extract_string(chunk.value, '$.text') IS NOT NULL
  GROUP BY ALL
)
SELECT
  project,
  ts,
  role,
  length(content) AS content_chars,
  CASE
    WHEN length(content) > 240 THEN left(content, 240) || '...'
    ELSE content
  END AS preview
FROM messages
WHERE '${KEYWORD_SQL}' <> ''
  AND contains(lower(content), lower('${KEYWORD_SQL}'))
  AND (${CODEX_SCOPE_PREDICATE})
ORDER BY ts DESC
LIMIT 20;
"
```

This first pass intentionally returns bounded previews only. If the previews are enough, continue to
Step 5. If you need the full message bodies or there are too many relevant hits to inspect safely in
the conversation, use Step 4 instead of widening this SELECT in place.

## Step 3 — Query Claude Code sessions (preview first, if available)

```bash
duckdb :memory: -c "
SELECT
  regexp_extract(filename, 'projects/([^/]+)/', 1) AS project,
  strftime(timestamp::TIMESTAMPTZ, '%Y-%m-%d %H:%M') AS ts,
  message.role AS role,
  length(message.content::VARCHAR) AS content_chars,
  CASE
    WHEN length(message.content::VARCHAR) > 240 THEN left(message.content::VARCHAR, 240) || '...'
    ELSE message.content::VARCHAR
  END AS preview
FROM read_ndjson('${HOME_SQL}/.claude/projects/*/*.jsonl', auto_detect=true, ignore_errors=true, filename=true)
WHERE '${KEYWORD_SQL}' <> ''
  AND message.content IS NOT NULL
  AND contains(lower(message.content::VARCHAR), lower('${KEYWORD_SQL}'))
  AND message.role IS NOT NULL
  AND (${CLAUDE_SCOPE_PREDICATE})
ORDER BY timestamp DESC
LIMIT 20;
"
```

If both Codex and Claude Code logs exist, run both source queries and merge the relevant findings.

## Step 4 — Handle large result sets

If a source has many matches, or the preview rows above are not enough to answer the question,
offload the full results to a temporary DuckDB file so you can query them interactively without
flooding the conversation context:

Resolve the state directory first:

```bash
STATE_DIR=""
test -d .duckdb-skills && STATE_DIR=".duckdb-skills"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
PROJECT_ID="$(echo "$PROJECT_ROOT" | tr '/' '-')"
test -d "$HOME/.duckdb-skills/$PROJECT_ID" && STATE_DIR="$HOME/.duckdb-skills/$PROJECT_ID"
# Fall back to project-local if neither exists
test -z "$STATE_DIR" && STATE_DIR=".duckdb-skills" && mkdir -p "$STATE_DIR"
```

Create the table using the same source query body you used above, but materialize full `content`
into a common schema instead of the preview-only columns:

```bash
duckdb "$STATE_DIR/memories.duckdb" -c "
CREATE OR REPLACE TABLE memories AS
SELECT
  '<SOURCE>' AS source,
  project,
  ts::TIMESTAMPTZ AS ts,
  role,
  content
FROM (
  <SOURCE_QUERY_BODY>
);
"
```

Replace `<SOURCE>` with `codex` or `claude`, and `<SOURCE_QUERY_BODY>` with the SELECT body from
the source query you actually used.

Then query the table interactively to drill down:

```bash
duckdb "$STATE_DIR/memories.duckdb" -c "SELECT count() FROM memories;"
duckdb "$STATE_DIR/memories.duckdb" -c "FROM memories WHERE contains(lower(content), lower('<narrower term>')) LIMIT 20;"
```

Clean up when done:

```bash
rm -f "$STATE_DIR/memories.duckdb"
```

## Step 5 — Internalize

From the results, extract:
- Decisions made and their rationale
- Patterns and conventions established
- Unresolved items or open TODOs
- Any corrections the user made to your prior behavior

Use this to inform your current response. Do not repeat back the raw logs to the user.

## Cross-skill integration

- **Session state**: If a `state.sql` exists (in `.duckdb-skills/` or `$HOME/.duckdb-skills/<project-id>/`), you can add the memories table to the session temporarily by appending an ATTACH to it — useful if the user wants to cross-reference memories with their data.
- **Error troubleshooting**: If DuckDB returns errors when reading JSONL logs, use the `duckdb-docs` skill to search for guidance.
