---
name: query
description: >
  Run SQL queries against the attached DuckDB database or ad-hoc against files.
  Accepts raw SQL or natural language questions. Uses DuckDB Friendly SQL idioms.
argument-hint: <SQL or question> [--file path]
allowed-tools: Bash
---

You are helping the user query data using DuckDB.

Input: `$@`

Follow these steps in order.

## Step 1 — Resolve state and determine the mode

Look for an existing state file in either location:

```bash
STATE_DIR=""
test -f .duckdb-skills/state.sql && STATE_DIR=".duckdb-skills"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
PROJECT_ID="$(echo "$PROJECT_ROOT" | tr '/' '-')"
test -f "$HOME/.duckdb-skills/$PROJECT_ID/state.sql" && STATE_DIR="$HOME/.duckdb-skills/$PROJECT_ID"
```

If found, verify the databases it references are still accessible:

```bash
duckdb -init "$STATE_DIR/state.sql" -c "SHOW DATABASES;"
```

Now determine the mode:

- **Ad-hoc mode** if: the `--file` flag is present, or the SQL references file paths/literals (e.g. `FROM 'data.csv'`), or `STATE_DIR` is empty.
- **Session mode** if: `STATE_DIR` is set and the input references table names, is natural language, or is SQL without file references.

If no state file exists and no file is referenced, fall back to ad-hoc mode against `:memory:` — the user must reference files directly in their SQL.

If the state file exists but any ATTACH in it fails, warn the user and fall back to ad-hoc mode.

## Step 2 — Check DuckDB is installed

```bash
command -v duckdb
```

If not found, delegate to `/duckdb-skills:install-duckdb` and then continue.

## Step 3 — Generate SQL if needed

If the input is natural language (not valid SQL), generate SQL using the Friendly SQL reference below.

In **session mode**, first retrieve the schema to inform query generation:

```bash
duckdb -init "$STATE_DIR/state.sql" -csv -c "
SELECT table_name FROM duckdb_tables() ORDER BY table_name;
"
```

Then for relevant tables:

```bash
duckdb -init "$STATE_DIR/state.sql" -csv -c "DESCRIBE <table_name>;"
```

Use the schema context and the Friendly SQL reference to generate the most appropriate query.

## Step 4 — Estimate result size

Before executing, estimate whether the query could produce a very large result that would
consume excessive tokens when returned to this conversation.

**Session mode** — check row counts for the tables involved:

```bash
duckdb -init "$STATE_DIR/state.sql" -csv -c "
SELECT table_name, estimated_size, column_count
FROM duckdb_tables()
WHERE table_name IN ('<table1>', '<table2>');
"
```

**Ad-hoc mode** — probe the source:

```bash
duckdb :memory: -csv -c "
SET allowed_paths=['FILE_PATH'];
SET enable_external_access=false;
SET allow_persistent_secrets=false;
SET lock_configuration=true;
SELECT count() AS row_count FROM 'FILE_PATH';
"
```

**Evaluate**:
- If the query already has a `LIMIT`, `count()`, or other aggregation that bounds the output -> safe, proceed.
- If the source has **>1M rows** and the query has no LIMIT or aggregation -> tell the user:
  *"This query would return a very large result set. Displaying it here would consume a lot of tokens and increase cost. I'd recommend adding `LIMIT 1000` or an aggregation to keep the output manageable."*
  Ask for confirmation before running as-is.
- If the data size is **>10 GB** -> additionally warn:
  *"This table is over 10 GB — the query may take a while to complete."*
  Proceed if the user confirms.

Skip this step for queries that are intrinsically bounded (e.g. `DESCRIBE`, `SUMMARIZE`, aggregations, `count()`).

## Step 5 — Execute the query

**Ad-hoc mode** (sandboxed — only the referenced file is accessible):

```bash
duckdb :memory: -csv <<'SQL'
SET allowed_paths=['FILE_PATH'];
SET enable_external_access=false;
SET allow_persistent_secrets=false;
SET lock_configuration=true;
<QUERY>;
SQL
```

Replace `FILE_PATH` with the actual file path extracted from the query or `--file` argument.
If multiple files are referenced, include all paths in the `allowed_paths` list.

**Session mode** (user-trusted database):

```bash
duckdb -init "$STATE_DIR/state.sql" -csv -c "<QUERY>"
```

For multi-line queries, use a heredoc with `-init`:

```bash
duckdb -init "$STATE_DIR/state.sql" -csv <<'SQL'
<QUERY>;
SQL
```

Always use heredocs (`<<'SQL'`) for multi-line queries to avoid shell quoting issues.

## Step 6 — Handle errors

- **Syntax error**: show the error, suggest a corrected query, and re-run.
- **Missing extension** (e.g. `Extension "X" not loaded`): delegate to `/duckdb-skills:install-duckdb <ext>`, then retry.
- **Table not found** (session mode): list available tables with `FROM duckdb_tables()` and suggest corrections.
- **File not found** (ad-hoc mode): use `find "$PWD" -name "<filename>" 2>/dev/null` to locate the file and suggest the corrected path.
- **Persistent or unclear DuckDB error**: use `/duckdb-skills:duckdb-docs <error message or relevant keywords>` to search the documentation for guidance, then apply the fix and retry.

## Step 7 — Present results

Show the query output to the user. If the result has more than 100 rows, note the truncation and suggest adding `LIMIT` to the query.

For natural language questions, also provide a brief interpretation of the results.

---

## DuckDB Friendly SQL Reference

When generating SQL, prefer these idiomatic DuckDB constructs:

### Compact clauses
- **FROM-first**: `FROM table WHERE x > 10` (implicit `SELECT *`)
- **GROUP BY ALL**: auto-groups by all non-aggregate columns
- **ORDER BY ALL**: orders by all columns for deterministic results
- **SELECT * EXCLUDE (col1, col2)**: drop columns from wildcard
- **SELECT * REPLACE (expr AS col)**: transform a column in-place
- **UNION ALL BY NAME**: combine tables with different column orders
- **Percentage LIMIT**: `LIMIT 10%` returns a percentage of rows
- **Prefix aliases**: `SELECT x: 42` instead of `SELECT 42 AS x`
- **Trailing commas** allowed in SELECT lists

### Query features
- **count()**: no need for `count(*)`
- **Reusable aliases**: use column aliases in WHERE / GROUP BY / HAVING
- **Lateral column aliases**: `SELECT i+1 AS j, j+2 AS k`
- **COLUMNS(*)**: apply expressions across columns; supports regex, EXCLUDE, REPLACE, lambdas
- **FILTER clause**: `count() FILTER (WHERE x > 10)` for conditional aggregation
- **GROUPING SETS / CUBE / ROLLUP**: advanced multi-level aggregation
- **Top-N per group**: `max(col, 3)` returns top 3 as a list; also `arg_max(arg, val, n)`, `min_by(arg, val, n)`
- **DESCRIBE table_name**: schema summary (column names and types)
- **SUMMARIZE table_name**: instant statistical profile
- **PIVOT / UNPIVOT**: reshape between wide and long formats
- **SET VARIABLE x = expr**: define SQL-level variables, reference with `getvariable('x')`

### Data import
- **Direct file queries**: `FROM 'file.csv'`, `FROM 'data.parquet'`
- **Globbing**: `FROM 'data/part-*.parquet'` reads multiple files
- **Auto-detection**: CSV headers and schemas are inferred automatically

### Expressions and types
- **Dot operator chaining**: `'hello'.upper()` or `col.trim().lower()`
- **List comprehensions**: `[x*2 FOR x IN list_col]`
- **List/string slicing**: `col[1:3]`, negative indexing `col[-1]`
- **STRUCT.* notation**: `SELECT s.* FROM (SELECT {'a': 1, 'b': 2} AS s)`
- **Square bracket lists**: `[1, 2, 3]`
- **format()**: `format('{}->{}', a, b)` for string formatting

### Joins
- **ASOF joins**: approximate matching on ordered data (e.g. timestamps)
- **POSITIONAL joins**: match rows by position, not keys
- **LATERAL joins**: reference prior table expressions in subqueries

### Data modification
- **CREATE OR REPLACE TABLE**: no need for `DROP TABLE IF EXISTS` first
- **CREATE TABLE ... AS SELECT (CTAS)**: create tables from query results
- **INSERT INTO ... BY NAME**: match columns by name, not position
- **INSERT OR IGNORE INTO / INSERT OR REPLACE INTO**: upsert patterns
