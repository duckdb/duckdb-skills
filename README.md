# duckdb-skills

A [Claude Code](https://claude.ai/code) plugin that adds DuckDB-powered skills for data exploration and session memory.

## Installation

### From the Discover tab (coming soon)

We are working on submitting this plugin to the official Anthropic marketplace. Once listed, it will appear in the **Discover** tab when you run `/plugin` inside Claude Code.

### From GitHub (available now)

Add the repository as a plugin source and install:

```
/plugin marketplace add duckdb/duckdb-skills
/plugin install duckdb-skills@duckdb-skills
```

This registers the GitHub repo as a marketplace and installs the plugin. Skills will be available as `/duckdb-skills:<skill-name>` in all future sessions.

## Skills

### `attach-db`
Attach a DuckDB database file for interactive querying. Explores the schema (tables, columns, row counts) and writes a SQL state file so all other skills can restore the session automatically. You can choose to store state in the project directory (`.duckdb-skills/state.sql`) or in your home directory (`~/.duckdb-skills/<project>/state.sql`).

```
/duckdb-skills:attach-db my_analytics.duckdb
```

Supports multiple databases — running `attach-db` again can append to the existing state file.

### `query`
Run SQL queries against attached databases or ad-hoc against files. Accepts raw SQL or natural language questions. Uses DuckDB's Friendly SQL dialect. Automatically picks up session state from `attach-db`.

```
/duckdb-skills:query FROM sales LIMIT 10
/duckdb-skills:query "what are the top 5 customers by revenue?"
/duckdb-skills:query FROM 'exports.csv' WHERE amount > 100
```

### `read-file`
Read and explore any data file — CSV, JSON, Parquet, Avro, Excel, spatial formats, and more — by filename only. Automatically resolves the path, detects the format via the [magic](https://github.com/carlopi/duckdb_magic) extension, and installs any required DuckDB extensions on the fly. Suggests `query` for further exploration.

```
/duckdb-skills:read-file variants.parquet what columns does it have?
```

### `duckdb-docs`
Search DuckDB and DuckLake documentation and blog posts using full-text search against the hosted search indexes. No local setup required.

```
/duckdb-skills:duckdb-docs window functions
/duckdb-skills:duckdb-docs "how do I read a CSV with custom delimiters?"
```

### `read-memories`
Search past Claude Code session logs to recover context from previous conversations — decisions made, patterns established, open TODOs. Offloads large result sets to a temporary DuckDB file for interactive drill-down.

```
/duckdb-skills:read-memories duckdb --here
```

### `install-duckdb`
Install or update DuckDB extensions. Supports `name@repo` syntax for community extensions and a `--update` flag that also checks whether your DuckDB CLI is on the latest stable version.

```
/duckdb-skills:install-duckdb spatial magic@community httpfs
/duckdb-skills:install-duckdb --update
```

## Local development

To test skills locally from a clone of this repo:

```bash
# 1. Clone the repo
git clone https://github.com/duckdb/duckdb-skills.git
cd duckdb-skills

# 2. Launch Claude Code with the local plugin directory
claude --plugin-dir .
```

This loads the plugin from disk instead of the marketplace, so any edits to `skills/*/SKILL.md` take effect immediately — just start a new conversation (or re-run the slash command) to pick up changes.

You can test individual skills directly:

```
/duckdb-skills:read-file some_local_file.parquet
/duckdb-skills:duckdb-docs pivot unpivot
/duckdb-skills:query SELECT 42
```

**Prerequisites:** DuckDB CLI must be installed. If it isn't, the skills will offer to install it via `/duckdb-skills:install-duckdb`.

## Reporting issues & suggestions

Found a bug or have an idea for improvement? Open an issue at:

**https://github.com/duckdb/duckdb-skills/issues**

For DuckDB-specific bugs (extension loading, SQL errors), please include the DuckDB version (`duckdb --version`) and the full error message.
