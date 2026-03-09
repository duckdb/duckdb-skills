# duckdb-claude-skills

A [Claude Code](https://claude.ai/code) plugin that adds DuckDB-powered skills for data exploration and session memory.

## Skills

### `read-file`
Read and explore any data file — CSV, JSON, Parquet, Avro, Excel, spatial formats, and more — by filename only. Automatically resolves the path, detects the format via the [magic](https://github.com/carlopi/duckdb_magic) extension, and installs any required DuckDB extensions on the fly.

```
/duckdb-claude-skills:read-file variants.parquet what columns does it have?
```

### `read-memories`
Search past Claude Code session logs to recover context from previous conversations — decisions made, patterns established, open TODOs. Invoke it proactively when you need to recall past work.

```
/duckdb-claude-skills:read-memories duckdb --here
```

### `install-duckdb`
Install or update DuckDB extensions. Supports `name@repo` syntax for community extensions and a `--update` flag that also checks whether your DuckDB CLI is on the latest stable version.

```
/duckdb-claude-skills:install-duckdb spatial magic@community httpfs
/duckdb-claude-skills:install-duckdb --update
```

## Installation

```bash
claude --plugin-dir /path/to/duckdb-claude-skills
```

## Reporting issues & suggestions

Found a bug or have an idea for improvement? Open an issue at:

**https://github.com/carlopi/duckdb-claude-skills/issues**

For DuckDB-specific bugs (extension loading, SQL errors), please include the DuckDB version (`duckdb --version`) and the full error message.
