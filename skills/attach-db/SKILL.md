---
name: attach-db
description: >
  Attach a DuckDB database file for use with /duckdb-skills:query.
  Explores the schema (tables, columns, row counts) and writes a SQL state file
  so subsequent queries can restore this session automatically via duckdb -init.
argument-hint: <path-to-database.duckdb>
allowed-tools: Bash
---

You are helping the user attach a DuckDB database file for interactive querying.

Database path given: `$0`

Follow these steps in order, stopping and reporting clearly if any step fails.

**State file convention**: see the "Resolve state directory" section below. All skills share a single `state.sql` file per project. Once resolved, any skill can use it with `duckdb -init "$STATE_DIR/state.sql" -c "<QUERY>"`.

## Step 1 — Resolve the database path

If `$0` is a relative path, resolve it against `$PWD` to get an absolute path (`RESOLVED_PATH`).

```bash
RESOLVED_PATH="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")"
```

Check the file exists:

```bash
test -f "$RESOLVED_PATH"
```

- **File exists** -> continue to Step 2.
- **File not found** -> ask the user if they want to create a new empty database (DuckDB creates the file on first write). If yes, continue. If no, stop.

## Step 2 — Check DuckDB is installed

```bash
command -v duckdb
```

If not found, delegate to `/duckdb-skills:install-duckdb` and then continue.

## Step 3 — Validate the database

```bash
duckdb "$RESOLVED_PATH" -c "PRAGMA version;"
```

- **Success** -> continue.
- **Failure** -> report the error clearly (e.g. corrupt file, not a DuckDB database) and stop.

## Step 4 — Explore the schema

First, list all tables:

```bash
duckdb "$RESOLVED_PATH" -csv -c "
SELECT table_name, estimated_size
FROM duckdb_tables()
ORDER BY table_name;
"
```

If the database has **no tables**, note that it is empty and skip to Step 5.

For each table discovered (up to 20), run:

```bash
duckdb "$RESOLVED_PATH" -csv -c "
DESCRIBE <table_name>;
SELECT count() AS row_count FROM <table_name>;
"
```

Collect the column definitions and row counts for the summary.

## Step 5 — Resolve the state directory

Check if a state file already exists in either location:

```bash
# Option 1: in the project directory
test -f .duckdb-skills/state.sql && STATE_DIR=".duckdb-skills"

# Option 2: in the home directory, scoped by project root path
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
PROJECT_ID="$(echo "$PROJECT_ROOT" | tr '/' '-')"
test -f "$HOME/.duckdb-skills/$PROJECT_ID/state.sql" && STATE_DIR="$HOME/.duckdb-skills/$PROJECT_ID"
```

If **neither exists**, ask the user:

> Where would you like to store the DuckDB session state for this project?
>
> 1. **In the project directory** (`.duckdb-skills/state.sql`) — colocated with the project, easy to find. You can choose to gitignore it.
> 2. **In your home directory** (`~/.duckdb-skills/<project-id>/state.sql`) — keeps the project directory clean.

Based on their choice:

**Option 1:**
```bash
STATE_DIR=".duckdb-skills"
mkdir -p "$STATE_DIR"
```
Then ask: *"Would you like to gitignore `.duckdb-skills/`?"* If yes:
```bash
echo '.duckdb-skills/' >> .gitignore
```

**Option 2:**
```bash
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
PROJECT_ID="$(echo "$PROJECT_ROOT" | tr '/' '-')"
STATE_DIR="$HOME/.duckdb-skills/$PROJECT_ID"
mkdir -p "$STATE_DIR"
```

## Step 6 — Append to the state file

`state.sql` is a shared, accumulative init file used by all duckdb-skills. It may already contain macros, LOAD statements, secrets, or other ATTACH statements written by other skills. **Never overwrite it** — always check for duplicates and append.

Derive the database alias from the filename without extension (e.g. `my_data.duckdb` → `my_data`). Check if this ATTACH already exists:

```bash
grep -q "ATTACH.*RESOLVED_PATH" "$STATE_DIR/state.sql" 2>/dev/null
```

If not already present, append:

```bash
cat >> "$STATE_DIR/state.sql" <<'STATESQL'
ATTACH IF NOT EXISTS 'RESOLVED_PATH' AS my_data;
USE my_data;
STATESQL
```

Replace `RESOLVED_PATH` and `my_data` with the actual values. If the alias would conflict with an existing one in the file, ask the user for a name.

## Step 7 — Verify the state file works

```bash
duckdb -init "$STATE_DIR/state.sql" -c "SHOW TABLES;"
```

If this fails, fix the state file and retry.

## Step 8 — Report

Summarize for the user:

- **Database path**: the resolved absolute path
- **Alias**: the database alias used in the state file
- **State file**: the resolved `STATE_DIR/state.sql` path
- **Tables**: name, column count, row count for each table (or note the DB is empty)
- Confirm the database is now active for `/duckdb-skills:query`

If the database is empty, suggest creating tables or importing data.
