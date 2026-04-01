#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_ROOT="$(mktemp -d /tmp/duckdb-skills-read-memories.XXXXXX)"
TEST_HOME="$TMP_ROOT/home"
REPO_MAIN="$TMP_ROOT/repo-main"
REPO_SUBDIR="$REPO_MAIN/subdir"
REPO_WORKTREE="$TMP_ROOT/repo-worktree"
UNRELATED_REPO="$TMP_ROOT/unrelated"
REPO_UNDERSCORE_MAIN="$TMP_ROOT/my_repo"
REPO_UNDERSCORE_SUBDIR="$REPO_UNDERSCORE_MAIN/subdir"
REPO_UNDERSCORE_NEAR="$TMP_ROOT/myXrepo"
REPO_UNDERSCORE_NEAR_SUBDIR="$REPO_UNDERSCORE_NEAR/subdir"
REPO_QUOTE_MAIN="$TMP_ROOT/repo-o'hare"
REPO_QUOTE_SUBDIR="$REPO_QUOTE_MAIN/subdir"
CLAUDE_COLLISION_ROOT="$TMP_ROOT/foo-bar"
CLAUDE_COLLISION_OTHER="$TMP_ROOT/foo/bar-baz"

cleanup() {
    rm -rf "$TMP_ROOT"
}

trap cleanup EXIT

if ! command -v duckdb >/dev/null 2>&1; then
    echo "ERROR: duckdb CLI not found."
    exit 1
fi

slugify_project() {
    echo "$1" | sed 's|[/_]|-|g'
}

escape_sql_literal() {
    printf '%s' "$1" | sed "s/'/''/g"
}

build_codex_scope_predicate() {
    local cwd="$1"
    local project_root
    local predicate=""

    project_root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || echo "$cwd")"

    while IFS= read -r root; do
        local root_sql
        [ -z "$root" ] && continue
        root_sql="$(escape_sql_literal "$root")"
        [ -n "$predicate" ] && predicate="$predicate OR "
        predicate="${predicate}(project = '${root_sql}' OR starts_with(project, '${root_sql}' || '/'))"
    done < <(
        {
            printf '%s\n' "$project_root"
            git -C "$project_root" worktree list --porcelain 2>/dev/null | awk '/^worktree / {print substr($0, 10)}'
        } | awk '!seen[$0]++'
    )

    printf '%s\n' "${predicate:-FALSE}"
}

build_claude_scope_predicate() {
    local cwd="$1"
    local project_root
    local predicate=""

    project_root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || echo "$cwd")"

    while IFS= read -r root; do
        local slug slug_sql
        [ -z "$root" ] && continue
        slug="$(slugify_project "$root")"
        slug_sql="$(escape_sql_literal "$slug")"
        [ -n "$predicate" ] && predicate="$predicate OR "
        predicate="${predicate}(project = '${slug_sql}')"
    done < <(
        {
            printf '%s\n' "$project_root"
            git -C "$project_root" worktree list --porcelain 2>/dev/null | awk '/^worktree / {print substr($0, 10)}'
        } | awk '!seen[$0]++'
    )

    printf '%s\n' "${predicate:-FALSE}"
}

write_codex_session() {
    local file="$1"
    local cwd="$2"
    local content="$3"

    mkdir -p "$(dirname "$file")"
    cat >"$file" <<EOF
{"timestamp":"2026-03-31T12:00:00Z","type":"session_meta","payload":{"cwd":"$cwd"}}
{"timestamp":"2026-03-31T12:01:00Z","type":"response_item","payload":{"role":"assistant","content":[{"type":"output_text","text":"$content"}]}}
EOF
}

write_claude_session() {
    local file="$1"
    local content="$2"

    mkdir -p "$(dirname "$file")"
    cat >"$file" <<EOF
{"timestamp":"2026-03-31T12:00:00Z","message":{"role":"assistant","content":"$content"}}
EOF
}

query_codex_projects() {
    local predicate="$1"
    local keyword="${2:-needle}"
    local keyword_sql

    keyword_sql="$(escape_sql_literal "$keyword")"

    HOME="$TEST_HOME" duckdb :memory: -csv <<SQL
WITH raw AS (
  SELECT filename, timestamp, type, payload
  FROM read_ndjson('$TEST_HOME/.codex/sessions/*/*/*/*.jsonl', auto_detect=true, ignore_errors=true, filename=true)
),
meta AS (
  SELECT filename, json_extract_string(payload, '$.cwd') AS project
  FROM raw
  WHERE type = 'session_meta'
),
messages AS (
  SELECT
    COALESCE(meta.project, '(unknown)') AS project,
    json_extract_string(raw.payload, '$.content[0].text') AS content
  FROM raw
  LEFT JOIN meta USING (filename)
  WHERE raw.type = 'response_item'
    AND json_extract_string(raw.payload, '$.role') IN ('user', 'assistant')
)
SELECT project
FROM messages
WHERE content ILIKE '%' || '${keyword_sql}' || '%'
  AND ($predicate)
ORDER BY project;
SQL
}

query_claude_projects() {
    local predicate="$1"
    local keyword="${2:-needle}"
    local keyword_sql

    keyword_sql="$(escape_sql_literal "$keyword")"

    HOME="$TEST_HOME" duckdb :memory: -csv <<SQL
SELECT regexp_extract(filename, 'projects/([^/]+)/', 1) AS project
FROM read_ndjson('$TEST_HOME/.claude/projects/*/*.jsonl', auto_detect=true, ignore_errors=true, filename=true)
WHERE message::VARCHAR ILIKE '%' || '${keyword_sql}' || '%'
  AND message.role IS NOT NULL
  AND ($predicate)
ORDER BY project;
SQL
}

normalize_project_rows() {
    tail -n +2 | sed 's/^"//; s/"$//'
}

mkdir -p "$TEST_HOME/.codex/sessions/2026/03/31" "$TEST_HOME/.claude/projects"
mkdir -p "$REPO_MAIN" "$REPO_SUBDIR" "$UNRELATED_REPO"
mkdir -p "$REPO_UNDERSCORE_MAIN" "$REPO_UNDERSCORE_SUBDIR" "$REPO_UNDERSCORE_NEAR_SUBDIR"
mkdir -p "$REPO_QUOTE_MAIN" "$REPO_QUOTE_SUBDIR"
mkdir -p "$CLAUDE_COLLISION_ROOT" "$CLAUDE_COLLISION_OTHER"

git -C "$REPO_MAIN" init -q
git -C "$REPO_MAIN" config user.email test@example.com
git -C "$REPO_MAIN" config user.name "DuckDB Skills Eval"
touch "$REPO_MAIN/.gitignore"
git -C "$REPO_MAIN" add .gitignore
git -C "$REPO_MAIN" commit -q -m "init"
git -C "$REPO_MAIN" worktree add -q "$REPO_WORKTREE"
git -C "$REPO_UNDERSCORE_MAIN" init -q
git -C "$REPO_QUOTE_MAIN" init -q

REPO_MAIN="$(cd "$REPO_MAIN" && pwd -P)"
REPO_SUBDIR="$(cd "$REPO_SUBDIR" && pwd -P)"
REPO_WORKTREE="$(cd "$REPO_WORKTREE" && pwd -P)"
UNRELATED_REPO="$(cd "$UNRELATED_REPO" && pwd -P)"
REPO_UNDERSCORE_MAIN="$(cd "$REPO_UNDERSCORE_MAIN" && pwd -P)"
REPO_UNDERSCORE_SUBDIR="$(cd "$REPO_UNDERSCORE_SUBDIR" && pwd -P)"
REPO_UNDERSCORE_NEAR="$(cd "$REPO_UNDERSCORE_NEAR" && pwd -P)"
REPO_UNDERSCORE_NEAR_SUBDIR="$(cd "$REPO_UNDERSCORE_NEAR_SUBDIR" && pwd -P)"
REPO_QUOTE_MAIN="$(cd "$REPO_QUOTE_MAIN" && pwd -P)"
REPO_QUOTE_SUBDIR="$(cd "$REPO_QUOTE_SUBDIR" && pwd -P)"
CLAUDE_COLLISION_ROOT="$(cd "$CLAUDE_COLLISION_ROOT" && pwd -P)"
CLAUDE_COLLISION_OTHER="$(cd "$CLAUDE_COLLISION_OTHER" && pwd -P)"

write_codex_session "$TEST_HOME/.codex/sessions/2026/03/31/main-root.jsonl" "$REPO_MAIN" "needle main root"
write_codex_session "$TEST_HOME/.codex/sessions/2026/03/31/main-subdir.jsonl" "$REPO_SUBDIR" "needle main subdir"
write_codex_session "$TEST_HOME/.codex/sessions/2026/03/31/worktree.jsonl" "$REPO_WORKTREE" "needle worktree"
write_codex_session "$TEST_HOME/.codex/sessions/2026/03/31/unrelated.jsonl" "$UNRELATED_REPO" "needle unrelated"
write_codex_session "$TEST_HOME/.codex/sessions/2026/03/31/underscore-main-subdir.jsonl" "$REPO_UNDERSCORE_SUBDIR" "needle underscore main"
write_codex_session "$TEST_HOME/.codex/sessions/2026/03/31/underscore-near.jsonl" "$REPO_UNDERSCORE_NEAR_SUBDIR" "needle underscore near"
write_codex_session "$TEST_HOME/.codex/sessions/2026/03/31/quoted-keyword.jsonl" "$REPO_MAIN" "o'hare keyword"
write_codex_session "$TEST_HOME/.codex/sessions/2026/03/31/quoted-path.jsonl" "$REPO_QUOTE_SUBDIR" "needle quote path"

write_claude_session "$TEST_HOME/.claude/projects/$(slugify_project "$REPO_MAIN")/main.jsonl" "needle main"
write_claude_session "$TEST_HOME/.claude/projects/$(slugify_project "$REPO_SUBDIR")/subdir.jsonl" "needle main subdir"
write_claude_session "$TEST_HOME/.claude/projects/$(slugify_project "$REPO_WORKTREE")/worktree.jsonl" "needle worktree"
write_claude_session "$TEST_HOME/.claude/projects/$(slugify_project "$UNRELATED_REPO")/unrelated.jsonl" "needle unrelated"
write_claude_session "$TEST_HOME/.claude/projects/$(slugify_project "$REPO_QUOTE_MAIN")/quoted-path.jsonl" "needle quote path"
write_claude_session "$TEST_HOME/.claude/projects/$(slugify_project "$CLAUDE_COLLISION_OTHER")/collision.jsonl" "needle collision"

CODEX_PROJECTS="$(query_codex_projects "$(build_codex_scope_predicate "$REPO_SUBDIR")" | normalize_project_rows)"
EXPECTED_CODEX="$(printf '%s\n' "$REPO_MAIN" "$REPO_SUBDIR" "$REPO_WORKTREE" | sort)"

if [ "$CODEX_PROJECTS" != "$EXPECTED_CODEX" ]; then
    echo "ERROR: Codex --here scope did not include the expected same-project roots"
    echo "Expected:"
    printf '%s\n' "$EXPECTED_CODEX"
    echo "Got:"
    printf '%s\n' "$CODEX_PROJECTS"
    exit 1
fi

CLAUDE_PROJECTS="$(query_claude_projects "$(build_claude_scope_predicate "$REPO_SUBDIR")" | normalize_project_rows)"
EXPECTED_CLAUDE="$(printf '%s\n' "$(slugify_project "$REPO_MAIN")" "$(slugify_project "$REPO_WORKTREE")" | sort)"

if [ "$CLAUDE_PROJECTS" != "$EXPECTED_CLAUDE" ]; then
    echo "ERROR: Claude --here scope did not keep the expected exact project/worktree matches"
    echo "Expected:"
    printf '%s\n' "$EXPECTED_CLAUDE"
    echo "Got:"
    printf '%s\n' "$CLAUDE_PROJECTS"
    exit 1
fi

CLAUDE_COLLISION_PROJECTS="$(query_claude_projects "$(build_claude_scope_predicate "$CLAUDE_COLLISION_ROOT")" | normalize_project_rows)"
EXPECTED_CLAUDE_COLLISION=""

if [ "$CLAUDE_COLLISION_PROJECTS" != "$EXPECTED_CLAUDE_COLLISION" ]; then
    echo "ERROR: Claude --here scope matched a slug-collision path"
    echo "Expected no matches"
    echo "Got:"
    printf '%s\n' "$CLAUDE_COLLISION_PROJECTS"
    exit 1
fi

UNDERSCORE_PROJECTS="$(query_codex_projects "$(build_codex_scope_predicate "$REPO_UNDERSCORE_SUBDIR")" | normalize_project_rows)"
EXPECTED_UNDERSCORE="$(printf '%s\n' "$REPO_UNDERSCORE_SUBDIR")"

if [ "$UNDERSCORE_PROJECTS" != "$EXPECTED_UNDERSCORE" ]; then
    echo "ERROR: Codex --here scope overmatched an underscore-like path"
    echo "Expected:"
    printf '%s\n' "$EXPECTED_UNDERSCORE"
    echo "Got:"
    printf '%s\n' "$UNDERSCORE_PROJECTS"
    exit 1
fi

QUOTED_KEYWORD_PROJECTS="$(query_codex_projects "$(build_codex_scope_predicate "$REPO_MAIN")" "o'hare" | normalize_project_rows)"
EXPECTED_QUOTED_KEYWORD="$(printf '%s\n' "$REPO_MAIN")"

if [ "$QUOTED_KEYWORD_PROJECTS" != "$EXPECTED_QUOTED_KEYWORD" ]; then
    echo "ERROR: Codex keyword search did not handle single quotes"
    echo "Expected:"
    printf '%s\n' "$EXPECTED_QUOTED_KEYWORD"
    echo "Got:"
    printf '%s\n' "$QUOTED_KEYWORD_PROJECTS"
    exit 1
fi

QUOTED_PATH_PROJECTS="$(query_codex_projects "$(build_codex_scope_predicate "$REPO_QUOTE_SUBDIR")" | normalize_project_rows)"
EXPECTED_QUOTED_PATH="$(printf '%s\n' "$REPO_QUOTE_SUBDIR")"

if [ "$QUOTED_PATH_PROJECTS" != "$EXPECTED_QUOTED_PATH" ]; then
    echo "ERROR: Codex --here scope did not handle a quoted project path"
    echo "Expected:"
    printf '%s\n' "$EXPECTED_QUOTED_PATH"
    echo "Got:"
    printf '%s\n' "$QUOTED_PATH_PROJECTS"
    exit 1
fi

CLAUDE_QUOTED_PATH_PROJECTS="$(query_claude_projects "$(build_claude_scope_predicate "$REPO_QUOTE_MAIN")" | normalize_project_rows)"
EXPECTED_CLAUDE_QUOTED_PATH="$(printf '%s\n' "$(slugify_project "$REPO_QUOTE_MAIN")")"

if [ "$CLAUDE_QUOTED_PATH_PROJECTS" != "$EXPECTED_CLAUDE_QUOTED_PATH" ]; then
    echo "ERROR: Claude --here scope did not handle a quoted project path"
    echo "Expected:"
    printf '%s\n' "$EXPECTED_CLAUDE_QUOTED_PATH"
    echo "Got:"
    printf '%s\n' "$CLAUDE_QUOTED_PATH_PROJECTS"
    exit 1
fi

echo "PASS: read-memories --here keeps same-project roots and excludes unrelated repos"
