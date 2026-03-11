# duckdb-skills

A [Claude Code](https://claude.ai/code) plugin that adds DuckDB-powered skills for data exploration and session memory.

## Installation

Inside Claude Code:

```
/plugin marketplace add duckdb/duckdb-skills
```
```
/plugin install duckdb-skills@duckdb-skills
```

Skills will be available as `/duckdb-skills:<skill-name>` in all future sessions.

## Skills

### `attach-db`
Attach a DuckDB database file for interactive querying. Explores the schema (tables, columns, row counts) and sets it as the active database for `/duckdb-skills:query`.

```
/duckdb-skills:attach-db my_analytics.duckdb
```

### `query`
Run SQL queries against the attached database or ad-hoc against files. Accepts raw SQL or natural language questions. Uses DuckDB's Friendly SQL dialect.

```
/duckdb-skills:query FROM sales LIMIT 10
/duckdb-skills:query "what are the top 5 customers by revenue?"
/duckdb-skills:query FROM 'exports.csv' WHERE amount > 100
```

### `read-file`
Read and explore any data file — CSV, JSON, Parquet, Avro, Excel, spatial formats, and more — by filename only. Automatically resolves the path, detects the format via the [magic](https://github.com/carlopi/duckdb_magic) extension, and installs any required DuckDB extensions on the fly.

```
/duckdb-skills:read-file variants.parquet what columns does it have?
```

### `read-memories`
Search past Claude Code session logs to recover context from previous conversations — decisions made, patterns established, open TODOs. Invoke it proactively when you need to recall past work.

```
/duckdb-skills:read-memories duckdb --here
```

### `install-duckdb`
Install or update DuckDB extensions. Supports `name@repo` syntax for community extensions and a `--update` flag that also checks whether your DuckDB CLI is on the latest stable version.

```
/duckdb-skills:install-duckdb spatial magic@community httpfs
/duckdb-skills:install-duckdb --update
```

**One-off / testing:**

```bash
claude --plugin-dir /path/to/duckdb-skills
```

## Reporting issues & suggestions

Found a bug or have an idea for improvement? Open an issue at:

**https://github.com/duckdb/duckdb-skills/issues**

For DuckDB-specific bugs (extension loading, SQL errors), please include the DuckDB version (`duckdb --version`) and the full error message.
