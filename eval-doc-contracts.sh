#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SKILL_REFS="$(rg -n '(/duckdb-skills:|duckdb-skills:)' "$ROOT/skills" --glob 'SKILL.md' || true)"

if [ -n "$SKILL_REFS" ]; then
    echo "ERROR: shared SKILL.md files must keep cross-skill references client-neutral."
    echo "$SKILL_REFS"
    exit 1
fi

if ! rg -q 'Examples below use the Claude Code slash-command form' "$ROOT/README.md"; then
    echo "ERROR: README must keep the Claude Code invocation contract explicit."
    exit 1
fi

if ! rg -q 'duckdb-skills:query SELECT 42' "$ROOT/README.md"; then
    echo "ERROR: README must document the Codex invocation form."
    exit 1
fi

if ! rg -q 'TARGET_HOME=/path/to/codex-home bash skills/install-duckdb/eval-codex.sh' "$ROOT/README.md"; then
    echo "ERROR: README must require an explicit TARGET_HOME for the Codex eval path."
    exit 1
fi

if rg -q '^bash skills/install-duckdb/eval-codex.sh$' "$ROOT/README.md"; then
    echo "ERROR: README must not advertise a standalone eval-codex invocation without TARGET_HOME."
    exit 1
fi

echo "PASS: doc contracts hold"
