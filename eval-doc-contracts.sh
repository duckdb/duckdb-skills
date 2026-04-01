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

if grep -Eq '<(KEYWORD_SQL|CODEX_SCOPE_PREDICATE|CLAUDE_SCOPE_PREDICATE)>' "$ROOT/skills/read-memories/SKILL.md"; then
    echo "ERROR: read-memories should interpolate shell variables directly instead of leaving placeholder tokens in the SQL snippets."
    exit 1
fi

if ! grep -Eq 'HAS_CODEX.*Step 2.*skip directly to Step 3' "$ROOT/skills/read-memories/SKILL.md"; then
    echo "ERROR: read-memories must explicitly gate the Codex preview query on HAS_CODEX."
    exit 1
fi

if ! grep -Eq 'HAS_CLAUDE.*Step 3.*skip it' "$ROOT/skills/read-memories/SKILL.md"; then
    echo "ERROR: read-memories must explicitly gate the Claude preview query on HAS_CLAUDE."
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
