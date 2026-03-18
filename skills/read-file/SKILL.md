---
name: read-file
description: >
  Read and explore any data file (CSV, JSON, Parquet, Avro, Excel, spatial, …)
  by filename only — resolves the path automatically. Uses DuckDB + the magic
  extension for format auto-detection. Installs magic if needed.
argument-hint: <filename> [question about the data]
allowed-tools: Bash
---

You are helping the user read and analyze a data file using DuckDB.

Filename given: `$0`
Question: `${1:-describe the data}`

Follow these steps in order, stopping and reporting clearly if any step fails.

## Step 1 — Resolve the filename to a full path

```bash
find "$PWD" -name "$0" -not -path '*/.git/*' 2>/dev/null
```

- **Zero results** → tell the user the file was not found and stop.
- **More than one result** → list all matches, ask the user to re-run with a fuller path, and stop.
- **Exactly one result** → use that full path for all subsequent steps (`RESOLVED_PATH`).

## Step 2 — Attempt to read the file (optimistic)

Try a sandboxed read without loading any extra extensions — this succeeds immediately for
built-in formats (CSV, plain text):

```bash
duckdb :memory: -csv -c "LOAD magic; SET allowed_paths=['RESOLVED_PATH']; SET enable_external_access=false; SET allow_persistent_secrets=false; SET lock_configuration=true; SELECT column_name FROM (DESCRIBE FROM read_any('RESOLVED_PATH')); SELECT count(*) AS row_count FROM read_any('RESOLVED_PATH'); FROM read_any('RESOLVED_PATH') LIMIT 10;"
```

**If this succeeds** → skip to Step 4 (Answer).

**If this fails** → diagnose the cause:
- **`duckdb: command not found`** → invoke `/duckdb-claude-skills:install-duckdb magic@community` to install DuckDB and magic, then retry this step.
- **Version too old** (e.g. `read_any` or `magic` not recognised) → invoke `/duckdb-claude-skills:install-duckdb --update magic@community` to upgrade, then retry this step.
- **Missing extension** → continue to Step 3.

Notes:
- All `LOAD` statements must precede `SET enable_external_access=false`.
- **Spatial files**: `st_read` globs for sidecar files using the filename stem. For spatial
  formats add a stem-wildcard to `allowed_paths`:
  `SET allowed_paths=['RESOLVED_PATH', 'RESOLVED_PATH_WITHOUT_EXTENSION.*']`

## Step 3 — Install required extensions and retry

Detect which extensions are needed, install them, then re-run the read:

```bash
# 3a — detect required extensions
duckdb :memory: -csv -c "INSTALL magic FROM community; LOAD magic; SELECT magic_required_extensions('RESOLVED_PATH') AS required_exts;"

# 3b — install all required extensions in one call (skip if list is empty)
duckdb :memory: -c "INSTALL <ext1>; INSTALL <ext2>;"

# 3c — retry the sandboxed read with all extensions loaded
duckdb :memory: -csv -c "LOAD magic; LOAD <ext1>; LOAD <ext2>; SET allowed_paths=['RESOLVED_PATH']; SET enable_external_access=false; SET allow_persistent_secrets=false; SET lock_configuration=true; SELECT column_name FROM (DESCRIBE FROM read_any('RESOLVED_PATH')); SELECT count(*) AS row_count FROM read_any('RESOLVED_PATH'); FROM read_any('RESOLVED_PATH') LIMIT 10;"
```

The three SELECT statements in 3c produce three result sets printed sequentially in CSV format.

## Step 4 — Answer the question

Using the schema, row count, and sample rows gathered above, answer:

`${1:-describe the data: summarize column types, row count, and any notable patterns.}`

## Step 5 — Suggest next steps

After answering, if the data looks like something the user might want to explore further (multiple columns, non-trivial row count), mention:

> *If you want to keep querying this data — filter, aggregate, join with other files — you can use `/duckdb-skills:query`. It supports SQL and natural language questions.*

If the file is large and the user might benefit from persisting it, also suggest:

> *To attach this as a database for repeated queries, run `/duckdb-skills:attach-db <path>`.*

Keep these suggestions brief and only show them once — don't repeat on follow-ups.

## Cross-skill integration

- **Session state**: If `$HOME/.duckdb-skills/state.sql` exists, the user has an active database session (set up via `/duckdb-skills:attach-db`). If the user asks follow-up queries about a file you just read, suggest using `/duckdb-skills:query` which will pick up any attached databases automatically.
- **Error troubleshooting**: If DuckDB returns a persistent or unclear error (e.g. unsupported format, extension issues), use `/duckdb-skills:duckdb-docs <error keywords>` to search the documentation for guidance.
