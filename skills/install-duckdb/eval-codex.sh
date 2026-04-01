#!/usr/bin/env bash
# End-to-end evaluations for the install-duckdb skill via Codex.
# Requires duckdb-skills to already be installed and enabled in the target Codex home.
#
# Prerequisites: codex CLI and duckdb must be in PATH. The target Codex home must already have
# duckdb-skills installed through /plugins and enabled in config.
#
# Usage:
#   TARGET_HOME=/path/to/codex-home bash skills/install-duckdb/eval-codex.sh
#   KEEP_TEMP=1 TARGET_HOME=/path/to/codex-home bash skills/install-duckdb/eval-codex.sh

PLUGIN_DIR="${PLUGIN_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
CODEX_BIN="${CODEX_BIN:-codex}"
TARGET_HOME="${TARGET_HOME:-}"
KEEP_TEMP="${KEEP_TEMP:-0}"
PASS=0
FAIL=0
TIMINGS=()
TMP_ROOT=""
if ! TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/duckdb-skills-codex-eval.XXXXXX")"; then
    echo "ERROR: failed to create temp directory for Codex eval." >&2
    exit 1
fi
if [ ! -d "$TMP_ROOT" ]; then
    echo "ERROR: temp directory was not created: $TMP_ROOT" >&2
    exit 1
fi

cleanup() {
    if [ "$KEEP_TEMP" = "1" ]; then
        echo "Keeping temp logs: $TMP_ROOT"
        return
    fi
    rm -rf "$TMP_ROOT"
}

slugify() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-'
}

run_codex() {
    local prompt="$1"
    local mode="$2"
    local output_file="$3"
    local log_file="$4"

    if [ "$mode" = "danger" ]; then
        HOME="$TARGET_HOME" "$CODEX_BIN" exec \
            --dangerously-bypass-approvals-and-sandbox \
            --skip-git-repo-check \
            -C "$PLUGIN_DIR" \
            -o "$output_file" \
            "$prompt" >"$log_file" 2>&1
        return
    fi

    HOME="$TARGET_HOME" "$CODEX_BIN" exec \
        --sandbox "$mode" \
        --skip-git-repo-check \
        -C "$PLUGIN_DIR" \
        -o "$output_file" \
        "$prompt" >"$log_file" 2>&1
}

require_plugin_smoke() {
    local output_file="$TMP_ROOT/plugin-smoke.txt"
    local log_file="$TMP_ROOT/plugin-smoke.log"
    local prompt="Use duckdb-skills:query SELECT 42. Reply with exactly one line: VALUE=42"

    if ! run_codex "$prompt" "read-only" "$output_file" "$log_file"; then
        echo "ERROR: Codex smoke test failed before install evals."
        echo "       Ensure duckdb-skills is already installed in the target Codex home."
        echo "       Last log lines: $(tail -n 5 "$log_file" 2>/dev/null | tr '\n' ' ')"
        exit 1
    fi

    if ! grep -qx 'VALUE=42' "$output_file"; then
        echo "ERROR: duckdb-skills did not respond to a Codex query smoke test."
        echo "       Install and enable the plugin in the target Codex home, then retry."
        echo "       Got: $(head -c 300 "$output_file" 2>/dev/null)"
        exit 1
    fi
}

eval_install_case() {
    local desc="$1"; shift
    local args="$1"; shift
    local exts=("$@")
    local slug output_file log_file prompt t0 t1 elapsed

    slug=$(slugify "$desc")
    output_file="$TMP_ROOT/${slug}.txt"
    log_file="$TMP_ROOT/${slug}.log"
    prompt="Use duckdb-skills:install-duckdb ${args}. Run the skill now. After it finishes, reply with exactly one line: STATUS=done"

    printf "  %-56s " "$desc"
    t0=$(date +%s)
    if ! run_codex "$prompt" "danger" "$output_file" "$log_file"; then
        t1=$(date +%s)
        elapsed=$((t1 - t0))
        TIMINGS+=("$elapsed")
        echo "FAIL  (${elapsed}s) - codex exec failed"
        echo "        log: $(tail -n 5 "$log_file" 2>/dev/null | tr '\n' ' ')"
        ((FAIL++))
        return
    fi
    t1=$(date +%s)
    elapsed=$((t1 - t0))
    TIMINGS+=("$elapsed")

    if ! grep -qx 'STATUS=done' "$output_file"; then
        echo "FAIL  (${elapsed}s) - unexpected skill output"
        echo "        got: $(head -c 300 "$output_file" 2>/dev/null)"
        ((FAIL++))
        return
    fi

    for ext in "${exts[@]}"; do
        if ! HOME="$TARGET_HOME" duckdb :memory: -c "LOAD ${ext};" &>/dev/null; then
            echo "FAIL  (${elapsed}s) - LOAD ${ext} failed after install"
            echo "        skill output: $(head -c 300 "$output_file" 2>/dev/null)"
            ((FAIL++))
            return
        fi
    done

    echo "PASS  (${elapsed}s)"
    ((PASS++))
}

eval_version_case() {
    local desc="$1"
    local slug output_file log_file prompt t0 t1 elapsed

    slug=$(slugify "$desc")
    output_file="$TMP_ROOT/${slug}.txt"
    log_file="$TMP_ROOT/${slug}.log"
    prompt="Use duckdb-skills:install-duckdb --update. Run the skill now. After it finishes, reply with one short sentence that includes any DuckDB CLI version numbers the skill reported."

    printf "  %-56s " "$desc"
    t0=$(date +%s)
    if ! run_codex "$prompt" "danger" "$output_file" "$log_file"; then
        t1=$(date +%s)
        elapsed=$((t1 - t0))
        TIMINGS+=("$elapsed")
        echo "FAIL  (${elapsed}s) - codex exec failed"
        echo "        log: $(tail -n 5 "$log_file" 2>/dev/null | tr '\n' ' ')"
        ((FAIL++))
        return
    fi
    t1=$(date +%s)
    elapsed=$((t1 - t0))
    TIMINGS+=("$elapsed")

    if grep -qE '[0-9]+\.[0-9]+\.[0-9]+' "$output_file"; then
        echo "PASS  (${elapsed}s)"
        ((PASS++))
    else
        echo "FAIL  (${elapsed}s) - no version number in output"
        echo "        got: $(head -c 300 "$output_file" 2>/dev/null)"
        ((FAIL++))
    fi
}

trap cleanup EXIT

if [ -z "$TARGET_HOME" ]; then
    echo "ERROR: TARGET_HOME must point to an initialized Codex home."
    echo "       Example: TARGET_HOME=/path/to/codex-home bash skills/install-duckdb/eval-codex.sh"
    exit 1
fi
if ! command -v "$CODEX_BIN" &>/dev/null; then
    echo "ERROR: '${CODEX_BIN}' CLI not found."
    exit 1
fi
if ! command -v duckdb &>/dev/null; then
    echo "ERROR: 'duckdb' CLI not found."
    exit 1
fi
if [ ! -d "$TARGET_HOME/.codex" ]; then
    echo "ERROR: target Codex home not found at $TARGET_HOME/.codex"
    echo "       Set TARGET_HOME to an initialized Codex home and retry."
    exit 1
fi

require_plugin_smoke

echo "=== install-duckdb skill eval (Codex) ==="
echo "Plugin dir  : $PLUGIN_DIR"
echo "Target home : $TARGET_HOME"
echo "Temp logs   : $TMP_ROOT"
echo ""

echo "--- Single extension (core) ---"
eval_install_case "Install httpfs"              "httpfs"                  httpfs
eval_install_case "Install json"                "json"                    json

echo ""
echo "--- Extension with @repo ---"
eval_install_case "Install gcs@community"       "gcs@community"           gcs

echo ""
echo "--- Multiple extensions ---"
eval_install_case "Install spatial + httpfs"    "spatial httpfs"          spatial httpfs
eval_install_case "Install spatial + gcs"       "spatial gcs@community"   spatial gcs

echo ""
echo "--- Update mode ---"
eval_install_case "Update all extensions"       "--update"
eval_install_case "Update specific extension"   "--update httpfs"

echo ""
echo "--- Version check (included in --update output) ---"
eval_version_case "Version info present in --update output"

echo ""
total=0
for t in "${TIMINGS[@]}"; do total=$((total + t)); done
count=${#TIMINGS[@]}
avg=$(( count > 0 ? total / count : 0 ))

echo "=================================="
echo "Results : $PASS passed, $FAIL failed"
echo "Timing  : total ${total}s, avg ${avg}s per case"
[ "$FAIL" -eq 0 ]
