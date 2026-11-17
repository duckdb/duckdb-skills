---
name: install-duckdb
description: >
  Install or update DuckDB extensions. Each argument is either a plain
  extension name (installs from core) or name@repo (e.g. magic@community).
  Pass --update to update extensions instead of installing. Also checks
  that the DuckDB CLI is present and, if it is not, suggests how to install
  it, system-wide or in a Python virtual environment.
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
> - or, in a Python virtual environment instead of system-wide: `pip install duckdb-cli` or `uv pip install duckdb-cli`
>
> Then re-run `/duckdb-skills:install-duckdb`.

Stop if DuckDB is not found.

If found, check whether it is the PyPI package `duckdb-cli`: its `duckdb` command is a Python script that mentions `duckdb_cli`, and its first line names the Python interpreter of the environment that owns it.

```bash
if grep -q duckdb_cli "$DUCKDB" 2>/dev/null; then
  PYTHON=$(head -1 "$DUCKDB" | sed 's/^#!//')
  VERSION=$("$DUCKDB" --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
fi
```

When `PYTHON` is set, core extensions are installed into that environment as packages, with `uv pip install --python "$PYTHON" ...` if `uv` is available and `"$PYTHON" -m pip install ...` otherwise. The CLI finds an extension installed that way without a download.

## Step 2 — Check for --update flag

If `--update` is present in `$@`, remove it from the argument list and set mode to **update**.
Otherwise mode is **install**.

## Step 3 — Build and run statements

**Install mode:**

Parse each remaining argument:
- If it contains `@`, split on `@` → `INSTALL <name> FROM <repo>;`
- Otherwise → `INSTALL <name>;`

When `PYTHON` is set, a plain `name` is a core extension and is installed as a package first, pinned to the CLI's version (the `.*` also admits a post-release of the same version):

```bash
uv pip install --python "$PYTHON" "duckdb-core-ext-<name>==$VERSION.*"
# or: "$PYTHON" -m pip install "duckdb-core-ext-<name>==$VERSION.*"
```

If that fails because no such package or version exists (an extension built into the CLI, or one that has no wheel for this version), fall back to `INSTALL <name>;`. A `name@repo` argument always goes through `INSTALL ... FROM`.

Run the remaining statements in a single DuckDB call:

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

  If the user agrees, detect how it was installed and run the appropriate upgrade command:
  - the PyPI package (`PYTHON` is set): upgrade the CLI and its extension packages together, so they stay on one version:
    `uv pip install --python "$PYTHON" "duckdb-cli==$LATEST" $(uv pip list --python "$PYTHON" | awk '/^duckdb-core-ext-/ {print $1 "==" "'"$LATEST"'.*"}')`
    (or the same through `"$PYTHON" -m pip`)
  - macOS (`brew` available): `brew upgrade duckdb`
  - Linux: `curl -fsSL https://install.duckdb.org | sh`
  - Windows: `winget upgrade DuckDB.cli`

Then update extensions. Extension packages were updated with the CLI above; `UPDATE EXTENSIONS` covers the ones installed with `INSTALL`:

- No extension names → update all: `UPDATE EXTENSIONS;`
- With extension names → update in a single call (ignore `@repo`):
  `UPDATE EXTENSIONS (<name1>, <name2>, ...);`

```bash
"$DUCKDB" :memory: -c "UPDATE EXTENSIONS;"
# or
"$DUCKDB" :memory: -c "UPDATE EXTENSIONS (<ext1>, <ext2>, ...);"
```

Report success or failure after the call completes.
