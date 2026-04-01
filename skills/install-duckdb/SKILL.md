---
name: install-duckdb
description: >
  Install or update DuckDB extensions. Each argument is either a plain
  extension name (installs from core) or name@repo (e.g. magic@community).
  Pass --update to update extensions instead of installing.
argument-hint: "[--update] [ext1 ext2@repo ext3 ...]"
allowed-tools: Bash
---

Arguments: `$@`

Each extension argument has the form `name` or `name@repo`.
- `name` → `INSTALL name;`
- `name@repo` → `INSTALL name FROM repo;`

## Step 1 — Locate DuckDB

```bash
DUCKDB=$(command -v duckdb)
```

If not found, tell the user:

> **DuckDB is not installed.** Install it first with one of:
> - macOS:   `brew install duckdb`
> - Linux:   `curl -fsSL https://install.duckdb.org | sh`
> - Windows: `winget install DuckDB.cli`
>
> Then re-run `duckdb-skills:install-duckdb`.

Stop if DuckDB is not found.

## Step 2 — Check for --update flag

If `--update` is present in `$@`, remove it from the argument list and set mode to **update**.
Otherwise mode is **install**.

## Step 3 — Build and run statements

**Install mode:**

Parse each remaining argument:
- If it contains `@`, split on `@` → `INSTALL <name> FROM <repo>;`
- Otherwise → `INSTALL <name>;`

Run all in a single DuckDB call:

```bash
"$DUCKDB" :memory: -c "INSTALL <ext1>; INSTALL <ext2> FROM <repo2>; ..."
```

**Update mode:**

First, check if the DuckDB CLI itself is up to date:

```bash
CURRENT=$(duckdb --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
LATEST=$(curl -fsSL https://duckdb.org/data/latest_stable_version.txt)
```

- If `CURRENT` == `LATEST` → report DuckDB CLI is up to date.
- If `CURRENT` != `LATEST` → ask the user:
  > **DuckDB CLI is outdated** (installed: `CURRENT`, latest: `LATEST`). Upgrade now?

  If the user agrees, detect the platform and run the appropriate upgrade command:
  - macOS (`brew` available): `brew upgrade duckdb`
  - Linux: `curl -fsSL https://install.duckdb.org | sh`
  - Windows: `winget upgrade DuckDB.cli`

Then update extensions:

- No extension names → update all: `UPDATE EXTENSIONS;`
- With extension names → update in a single call (ignore `@repo`):
  `UPDATE EXTENSIONS (<name1>, <name2>, ...);`

```bash
"$DUCKDB" :memory: -c "UPDATE EXTENSIONS;"
# or
"$DUCKDB" :memory: -c "UPDATE EXTENSIONS (<ext1>, <ext2>, ...);"
```

Report success or failure after the call completes.
