#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SKILL_REFS="$(find "$ROOT/skills" -name 'SKILL.md' -exec grep -nE '(/duckdb-skills:|duckdb-skills:)' {} + 2>/dev/null || true)"

if [ -n "$SKILL_REFS" ]; then
    echo "ERROR: shared SKILL.md files must keep cross-skill references client-neutral."
    echo "$SKILL_REFS"
    exit 1
fi

if ! grep -Fq 'Examples below use the Claude Code slash-command form' "$ROOT/README.md"; then
    echo "ERROR: README must keep the Claude Code invocation contract explicit."
    exit 1
fi

if ! grep -Fq 'Examples below use the Claude Code slash-command form. In Codex, invoke the same installed skill through the plugin by dropping the leading slash, for example `duckdb-skills:query SELECT 42` or `duckdb-skills:read-file variants.parquet what columns does it have?`.' "$ROOT/README.md"; then
    echo "ERROR: README must keep the Codex inline examples on one line."
    exit 1
fi

if ! grep -Fq 'TARGET_HOME=/path/to/codex-home bash skills/install-duckdb/eval-codex.sh' "$ROOT/README.md"; then
    echo "ERROR: README must require an explicit TARGET_HOME for the Codex eval path."
    exit 1
fi

if grep -Fxq 'bash skills/install-duckdb/eval-codex.sh' "$ROOT/README.md"; then
    echo "ERROR: README must not advertise a standalone eval-codex invocation without TARGET_HOME."
    exit 1
fi

echo "PASS: doc contracts hold"
