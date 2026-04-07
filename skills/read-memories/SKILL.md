---
name: read-memories
description: >
  Search past Codex or Claude Code session logs to recall prior decisions, patterns, or unresolved
  work. Use when user says "do you remember", "what did we do", references past conversations, or
  you need context from prior sessions.
argument-hint: <keyword> [--here]
allowed-tools: Bash
---

Search past session logs silently — do NOT narrate the process. Absorb the results and continue
with enriched context.

`$0` is the keyword. Pass `--here` as `$1` to scope to the current project only.

## Step 1 — Choose the source

- If `$0` is empty, stop and tell the user `read-memories` requires a non-empty keyword.
- Claude Code search paths:
  - All projects: `$HOME/.claude/projects/*/*.jsonl`
  - Current only (`--here`): `$HOME/.claude/projects/$(echo "$PWD" | sed 's|[/_]|-|g')/*.jsonl`
- Codex search path: `$HOME/.codex/sessions/*/*/*/*.jsonl`
- For Codex `--here`, resolve `<PROJECT_ROOT>` with `git rev-parse --show-toplevel 2>/dev/null || echo "$PWD"` and filter rows with `project = '<PROJECT_ROOT>' OR starts_with(project, '<PROJECT_ROOT>/')`.

## Step 2 — Query Claude Code

```bash
duckdb :memory: -c "
SELECT
  regexp_extract(filename, 'projects/([^/]+)/', 1) AS project,
  strftime(timestamp::TIMESTAMPTZ, '%Y-%m-%d %H:%M') AS ts,
  message.role AS role,
  left(message.content::VARCHAR, 500) AS content
FROM read_ndjson('<SEARCH_PATH>', auto_detect=true, ignore_errors=true, filename=true)
WHERE message.content IS NOT NULL
  AND contains(lower(message.content::VARCHAR), lower('<KEYWORD>'))
  AND message.role IS NOT NULL
ORDER BY timestamp
LIMIT 40;
"
```

Replace `<SEARCH_PATH>` and `<KEYWORD>` before running.

## Step 3 — Query Codex

```bash
duckdb :memory: -c "
WITH raw AS (
  SELECT filename, timestamp, type, payload
  FROM read_ndjson('$HOME/.codex/sessions/*/*/*/*.jsonl', auto_detect=true, ignore_errors=true, filename=true)
),
meta AS (
  SELECT filename, json_extract_string(payload, '$.cwd') AS project
  FROM raw
  WHERE type = 'session_meta'
),
messages AS (
  SELECT
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
  left(content, 500) AS content
FROM messages
WHERE contains(lower(content), lower('<KEYWORD>'))
  AND <CODEX_SCOPE_PREDICATE>
ORDER BY ts
LIMIT 40;
"
```

Replace `<KEYWORD>` before running. Use `1=1` for all projects, or use the `--here` predicate from
Step 1 for `<CODEX_SCOPE_PREDICATE>`.

## Step 4 — Internalize

From the results, extract decisions, patterns, unresolved TODOs, and user corrections. Use this to
inform your current response — do not repeat raw logs to the user.
