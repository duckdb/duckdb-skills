#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_FILE="$(mktemp "${TMPDIR:-/tmp}/duckdb-skills-codex-guard.XXXXXX")"
TMPDIR_FAIL_LOG="$(mktemp "${TMPDIR:-/tmp}/duckdb-skills-codex-guard.XXXXXX")"

cleanup() {
    rm -f "$LOG_FILE"
    rm -f "$TMPDIR_FAIL_LOG"
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

if env TMPDIR=/dev/null TARGET_HOME=/tmp/unused bash "$ROOT/skills/install-duckdb/eval-codex.sh" >"$TMPDIR_FAIL_LOG" 2>&1; then
    echo "ERROR: eval-codex.sh succeeded when temp directory creation should fail"
    cat "$TMPDIR_FAIL_LOG"
    exit 1
fi

if ! grep -q 'failed to create temp directory for Codex eval' "$TMPDIR_FAIL_LOG"; then
    echo "ERROR: eval-codex.sh did not fail with the expected temp directory guidance"
    cat "$TMPDIR_FAIL_LOG"
    exit 1
fi

echo "PASS: eval-codex.sh requires explicit TARGET_HOME"
