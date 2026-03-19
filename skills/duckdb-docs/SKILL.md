---
name: duckdb-docs
description: >
  Search DuckDB and DuckLake documentation and blog posts. Returns relevant
  doc chunks for a question or keyword using full-text search against the
  hosted search indexes. No local setup required — queries directly over httpfs.
argument-hint: <question or keyword>
allowed-tools: Bash
---

You are helping the user find relevant DuckDB or DuckLake documentation.

Query: `$@`

Follow these steps in order.

## Step 1 — Check DuckDB is installed

```bash
command -v duckdb
```

If not found, delegate to `/duckdb-skills:install-duckdb` and then continue.

## Step 2 — Ensure required extensions are installed

```bash
duckdb :memory: -c "INSTALL httpfs; INSTALL fts;"
```

If this fails, report the error and stop.

## Step 3 — Resolve state directory

Look for an existing state file:

```bash
STATE_DIR=""
test -f .duckdb-skills/state.sql && STATE_DIR=".duckdb-skills"
PROJECT_NAME="$(basename "$PWD")"
test -f "$HOME/.duckdb-skills/$PROJECT_NAME/state.sql" && STATE_DIR="$HOME/.duckdb-skills/$PROJECT_NAME"
```

If `STATE_DIR` is empty, this skill can still work without state (querying remotely). But if a local cache is created in Step 5, state will be needed — ask the user the same location question as `/duckdb-skills:attach-db` at that point.

## Step 4 — Choose the data source and extract search terms

The query is: `$@`

### Data source selection

There are two search indexes available:

| Index | Remote URL | Local cache filename | Versions | Use when |
|-------|-----------|---------------------|----------|----------|
| **DuckDB docs + blog** | `https://duckdb.org/data/docs-search.duckdb` | `duckdb-docs.duckdb` | `stable`, `current`, `blog` | Default — any DuckDB question |
| **DuckLake docs** | `https://ducklake.select/data/docs-search.duckdb` | `ducklake-docs.duckdb` | `stable`, `preview` | Query mentions DuckLake, catalogs, or DuckLake-specific features |

Both indexes share the same schema:

| Column | Type | Description |
|--------|------|-------------|
| `chunk_id` | `VARCHAR` (PK) | e.g. `stable/sql/functions/numeric#absx` |
| `page_title` | `VARCHAR` | Page title from front matter |
| `section` | `VARCHAR` | Section heading (null for page intros) |
| `breadcrumb` | `VARCHAR` | e.g. `SQL > Functions > Numeric` |
| `url` | `VARCHAR` | URL path with anchor |
| `version` | `VARCHAR` | See table above |
| `text` | `TEXT` | Full markdown of the chunk |

By default, search **DuckDB docs** and filter to `version = 'stable'`. Use different versions when:

- The user explicitly asks about `current`/nightly features → `version = 'current'`
- The user asks about a blog post or wants background/motivation → `version = 'blog'`
- The user asks about DuckLake → search the DuckLake index with `version = 'stable'`
- When unsure, omit the version filter to search across all versions.

### Search terms

If the input is a **natural language question** (e.g. "how do I find the most frequent value"), extract the key technical terms (nouns, function names, SQL keywords) to form a compact BM25 query string. Drop stop words like "how", "do", "I", "the".

If the input is already a **function name or technical term** (e.g. `arg_max`, `GROUP BY ALL`), use it as-is.

Use the extracted terms as `SEARCH_QUERY` in the next step.

## Step 5 — Check for local cache or offer to create one

Check if a local copy of the docs index already exists:

```bash
test -n "$STATE_DIR" && test -f "$STATE_DIR/duckdb-docs.duckdb"
```

(Or `ducklake-docs.duckdb` for DuckLake queries.)

**If a local cache exists** → check its age:

```bash
CACHE_FILE="$STATE_DIR/duckdb-docs.duckdb"
# macOS uses stat -f %m, Linux uses stat -c %Y
MTIME=$(stat -f %m "$CACHE_FILE" 2>/dev/null || stat -c %Y "$CACHE_FILE")
CACHE_AGE_DAYS=$(( ( $(date +%s) - MTIME ) / 86400 ))
```

- **2 days old or less** → use it directly (skip to Step 6).
- **Older than 2 days** → silently refresh it by deleting the file and re-running the COPY FROM DATABASE below. No need to ask the user.

**If no local cache exists** → this is the first docs query. Ask the user:

> To avoid repeated HTTP calls to the remote docs index, I can create a local copy in your project's state directory. This makes future searches faster and works offline. Would you like me to cache it locally?

If the user agrees (and `STATE_DIR` is empty, ask for their preferred location first):

```bash
duckdb :memory: -c "
LOAD httpfs;
LOAD fts;
ATTACH 'INDEX_URL' AS remote_docs (READ_ONLY);
ATTACH '$STATE_DIR/duckdb-docs.duckdb' AS local_docs;
COPY FROM DATABASE remote_docs TO local_docs;
"
```

Then add the ATTACH to `state.sql` so it's available to all skills:

```bash
grep -q "duckdb-docs.duckdb" "$STATE_DIR/state.sql" 2>/dev/null || cat >> "$STATE_DIR/state.sql" <<'SQL'
LOAD fts;
ATTACH IF NOT EXISTS 'STATE_DIR/duckdb-docs.duckdb' AS docs (READ_ONLY);
SQL
```

Replace `STATE_DIR` with the actual resolved path.

**If the user declines** → query remotely (the original behavior).

## Step 6 — Search the docs

**With local cache** (use state.sql):

```bash
duckdb -init "$STATE_DIR/state.sql" -json -c "
USE docs;
SELECT
    chunk_id, page_title, section, breadcrumb, url, version, text,
    fts_main_docs_chunks.match_bm25(chunk_id, 'SEARCH_QUERY') AS score
FROM docs_chunks
WHERE score IS NOT NULL
  AND version = 'VERSION'
ORDER BY score DESC
LIMIT 8;
"
```

**Without local cache** (remote query):

```bash
duckdb :memory: -json <<'SQL'
LOAD httpfs;
LOAD fts;
ATTACH 'INDEX_URL' AS docs (READ_ONLY);
USE docs;
SELECT
    chunk_id, page_title, section, breadcrumb, url, version, text,
    fts_main_docs_chunks.match_bm25(chunk_id, 'SEARCH_QUERY') AS score
FROM docs_chunks
WHERE score IS NOT NULL
  AND version = 'VERSION'
ORDER BY score DESC
LIMIT 8;
SQL
```

Replace `INDEX_URL`, `SEARCH_QUERY`, and `VERSION` per Step 4. Remove the `AND version = 'VERSION'` line if searching across all versions.

If the user's question could benefit from both DuckDB docs and blog results, run two queries (one with `version = 'stable'`, one with `version = 'blog'`) or omit the version filter entirely.

## Step 7 — Handle errors

- **Extension not installed** (`httpfs` or `fts` not found): run `duckdb :memory: -c "INSTALL httpfs; INSTALL fts;"` and retry Step 6.
- **ATTACH fails / network unreachable**: inform the user that the docs index is unavailable and suggest checking their internet connection. The DuckDB index is hosted at `https://duckdb.org/data/docs-search.duckdb` and the DuckLake index at `https://ducklake.select/data/docs-search.duckdb`.
- **Local cache stale**: the cache auto-refreshes after 2 days, but if results seem outdated sooner, delete the local file and re-run the query to force a refresh.
- **No results** (all scores NULL or empty result set): try broadening the query — drop the least specific term, or try a single-word version of the query — then retry Step 6. If still no results, tell the user no matching documentation was found and suggest visiting https://duckdb.org/docs or https://ducklake.select/docs directly.

## Step 8 — Present results

For each result chunk returned (ordered by score descending), format as:

```
### {section} — {page_title}
{url}

{text}

---
```

After presenting all chunks, synthesize a concise answer to the user's original question (`$@`) based on the retrieved documentation. If the chunks directly answer the question, lead with the answer before showing the sources.
