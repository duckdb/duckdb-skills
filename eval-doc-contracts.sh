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

if ! grep -Eq 'Examples below use the Claude Code slash-command form\..*`duckdb-skills:query SELECT 42`.*`duckdb-skills:read-file variants\.parquet what columns does it have\?`' "$ROOT/README.md"; then
    echo "ERROR: README must keep the Codex invocation contract and inline examples intact."
    exit 1
fi

if ! grep -Fq '$HOME/.claude/projects/*/*.jsonl' "$ROOT/skills/read-memories/SKILL.md"; then
    echo "ERROR: read-memories must keep the Claude log path explicit."
    exit 1
fi

if ! grep -Fq '$HOME/.codex/sessions/*/*/*/*.jsonl' "$ROOT/skills/read-memories/SKILL.md"; then
    echo "ERROR: read-memories must keep the Codex log path explicit."
    exit 1
fi

if ! grep -Fq 'For Codex `--here`' "$ROOT/skills/read-memories/SKILL.md" || ! grep -Fq '<PROJECT_ROOT>' "$ROOT/skills/read-memories/SKILL.md"; then
    echo "ERROR: read-memories must keep the Codex --here guidance explicit."
    exit 1
fi

if ! grep -Fq 'Claude Code search paths:' "$ROOT/skills/read-memories/SKILL.md" || ! grep -Fq 'Current only (`--here`):' "$ROOT/skills/read-memories/SKILL.md"; then
    echo "ERROR: read-memories must keep the Claude --here guidance explicit."
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
