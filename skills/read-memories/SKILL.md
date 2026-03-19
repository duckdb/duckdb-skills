---
name: read-memories
description: >
  Search past Claude Code session logs to recover your own context.
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

## Step 1 — Set the search path

```bash
ALL_PROJECTS="$HOME/.claude/projects/*/*.jsonl"
CURRENT_PROJECT="$HOME/.claude/projects/$(echo "$PWD" | sed 's|[/_]|-|g')/*.jsonl"
```

Use `$CURRENT_PROJECT` if `$1` is `--here`, otherwise use `$ALL_PROJECTS`.

## Step 2 — Query

```bash
duckdb :memory: -c "
SELECT
  regexp_extract(filename, 'projects/([^/]+)/', 1) AS project,
  strftime(timestamp::TIMESTAMPTZ, '%Y-%m-%d %H:%M') AS ts,
  message.role AS role,
  message.content::VARCHAR AS content
FROM read_ndjson('<SEARCH_PATH>', auto_detect=true, ignore_errors=true, filename=true)
WHERE message::VARCHAR ILIKE '%<KEYWORD>%'
  AND message.role IS NOT NULL
ORDER BY timestamp
LIMIT 40;
"
```

Replace `<SEARCH_PATH>` and `<KEYWORD>` with the resolved values before running.

## Step 3 — Handle large result sets

If Step 2 returns more than 40 rows or the output is very large, offload the results to a temporary DuckDB file so you can query them interactively without flooding the conversation context:

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

```bash
duckdb "$STATE_DIR/memories.duckdb" -c "
CREATE OR REPLACE TABLE memories AS
SELECT
  regexp_extract(filename, 'projects/([^/]+)/', 1) AS project,
  timestamp::TIMESTAMPTZ AS ts,
  message.role AS role,
  message.content::VARCHAR AS content
FROM read_ndjson('<SEARCH_PATH>', auto_detect=true, ignore_errors=true, filename=true)
WHERE message::VARCHAR ILIKE '%<KEYWORD>%'
  AND message.role IS NOT NULL
ORDER BY timestamp;
"
```

Then query the table interactively to drill down:

```bash
duckdb "$STATE_DIR/memories.duckdb" -c "SELECT count() FROM memories;"
duckdb "$STATE_DIR/memories.duckdb" -c "FROM memories WHERE content ILIKE '%<narrower term>%' LIMIT 20;"
```

Clean up when done:

```bash
rm -f "$STATE_DIR/memories.duckdb"
```

## Step 4 — Internalize

From the results, extract:
- Decisions made and their rationale
- Patterns and conventions established
- Unresolved items or open TODOs
- Any corrections the user made to your prior behavior

Use this to inform your current response. Do not repeat back the raw logs to the user.

## Cross-skill integration

- **Session state**: If a `state.sql` exists (in `.duckdb-skills/` or `$HOME/.duckdb-skills/<project-id>/`), you can add the memories table to the session temporarily by appending an ATTACH to it — useful if the user wants to cross-reference memories with their data.
- **Error troubleshooting**: If DuckDB returns errors when reading JSONL logs, use `/duckdb-skills:duckdb-docs <error keywords>` to search for guidance.
