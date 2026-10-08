-- luna.sql: Lunas are rows. agents.luna_runs is what the Lunas did; agents.work is what still needs doing.
-- The launch is one cron line (cron.sql): codex exec with the prompt "SELECT * FROM agents.work LIMIT 1".
-- The Luna runs that on dev, gets its row, and works inside DuckDB (shellfs, duck_tails, read_json on GitHub).
-- Boots after open_prs.sql, whose CTAS is the only definition of open_prs_waiting.

-- Every Luna worktree: branch and last commit from duck_tails, activity from the live codex sessions (agent_data).
CREATE OR REPLACE VIEW agents.luna_runs AS
WITH worktrees AS (
  SELECT path AS worktree FROM ls('/Users/aloksubbarao/worktrees/luna-ci') WHERE is_dir(path) AND path_exists(path || '/.git')
), head AS (
  SELECT w.worktree, b.branch_name, b.commit_hash
  FROM worktrees w CROSS JOIN LATERAL git_branches_each(w.worktree) b
  WHERE b.is_current
), commits AS (
  SELECT w.worktree, max_by(l.message, l.commit_date) AS last_message, max(l.commit_date) AS last_commit
  FROM worktrees w CROSS JOIN LATERAL git_log_each(w.worktree) l
  GROUP BY w.worktree
), live AS (
  SELECT cwd AS worktree, max(TRY_CAST(timestamp AS TIMESTAMPTZ)) AS last_ts
  FROM read_conversations(source := 'codex', path := getenv('HOME') || '/.codex')
  GROUP BY cwd
)
SELECT h.worktree, h.branch_name, h.commit_hash, split_part(c.last_message, chr(10), 1) AS subject, c.last_commit,
       v.last_ts AS last_activity, v.last_ts > now() - INTERVAL 10 MINUTE AS running
FROM head h
LEFT JOIN commits c USING (worktree)
LEFT JOIN live v USING (worktree)
ORDER BY c.last_commit DESC;

-- One row per open PR of mine whose CI is red because of the PR (open_prs.sql), minus the ones a Luna
-- already has a worktree for (luna_runs). The task column is the whole brief.
CREATE OR REPLACE VIEW agents.work AS
WITH red AS (
  SELECT repo, number, title, idle_days,
         format('/Users/aloksubbarao/worktrees/luna-ci/{0}-{1}', replace(repo, '/', '-'), number) AS worktree
  FROM open_prs_waiting
  WHERE whose_move = 'mine: CI red' AND NOT starts_with(repo, 'inframe-risk/')
)
SELECT repo, number, title, idle_days, worktree,
       format('CI is red on {0} PR #{1} ({2}). Clone it into {3} and check the PR out. Read the PR, its failing checks and job logs as rows (read_json over api.github.com with GITHUB_TOKEN=$(gh auth token --user asubbarao); duck_hunt for logs; duck_tails for the repo). If the base branch fails the same way, a fix exists on another branch, or the failure is not this PR''s, report and exit without editing. Otherwise the smallest in-scope fix, tested, exactly one commit ending with the trailer "Co-Authored-By: Codex Luna 5.6 <noreply@openai.com>", pushed to the PR head branch only, never --force. No PR comments, no opening/closing/merging. Final message: root cause, files and commit sha, what you tested, pushed or not, what you did NOT change.',
              repo, number, title, worktree) AS task
FROM red ANTI JOIN agents.luna_runs USING (worktree)
ORDER BY idle_days DESC;
