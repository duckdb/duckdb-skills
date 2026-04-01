#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_FILE="$(mktemp /tmp/duckdb-skills-codex-guard.XXXXXX)"

cleanup() {
    rm -f "$LOG_FILE"
}

trap cleanup EXIT

if env -u TARGET_HOME bash "$ROOT/skills/install-duckdb/eval-codex.sh" >"$LOG_FILE" 2>&1; then
    echo "ERROR: eval-codex.sh succeeded without TARGET_HOME"
    cat "$LOG_FILE"
    exit 1
fi

if ! grep -q 'TARGET_HOME must point to an initialized Codex home' "$LOG_FILE"; then
    echo "ERROR: eval-codex.sh did not fail with the expected TARGET_HOME guidance"
    cat "$LOG_FILE"
    exit 1
fi

echo "PASS: eval-codex.sh requires explicit TARGET_HOME"
