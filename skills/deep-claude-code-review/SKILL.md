---
name: deep-claude-code-review
description: >-
  Claude-only variant of deep-pr-review: several independent Claude Code subagents review the same change at the highest effort available, findings merged by agreement. Reviews a GitHub PR URL and posts inline comments after per-comment confirmation, or, with no PR, reviews the current branch or working tree and writes deep-review.local.md. Use only when the user asks for a Claude-only deep review or runs /deep-claude-code-review.

disable-model-invocation: true
user-invocable: true
argument-hint: "[--non-interactive] <pr-url>"
metadata:
  version: "2"
---

# Deep Claude Code Review

1. Parse the GitHub PR URL from the user message, if any. Reviewers are Claude Code subagents on the current Claude Opus model at the highest effort level available; run at least three so agreement means something.
2. Launch one independent review per reviewer in parallel (host Task/subagent). Each reviewer returns findings tagged by the following severity tags: `act on`, `consider`, `noted`, or `dismissed`.
3. If two or more reviewers agree on a finding, merge them into a single finding and record the agreement count.
4. Sort the findings by severity (`act-on` > `consider` > `noted` > `dismissed`) and by the number of reviewers that agree on it.
5. Each finding will be posted as a single comment. Don't post a comment yet.

## No PR

When the user gives no PR URL, review the current branch against `origin/main` (`git diff origin/main...HEAD`), or the whole working tree if they ask for that. Run the same reviewers and merge the same way, then write the findings to `deep-review.local.md` in the repo root (it matches `*.local.*` in `.gitignore`) instead of posting anything. Use the same severity tags and the same writing rules; cite `path:line`.

## Post

- Inline review comments only after showing them to the user and asking for confirmation, unless `--non-interactive` was passed — in that case skip confirmation and post every `act on` and `consider` finding directly. Show comments one by one, i.e., show a comment, ask for confirmation, show the next comment, and so on.
- If you are afraid the comment shown will be blocked by the question asked using AskUserQuestion, then you should make the comment part of the question so the user can read it. Along with the comment you want to post, also mention its severity, the reviewers that flagged it, and any other relevant metadata.
- In both modes, never post `noted` or `dismissed` findings as comments.
- Do not edit the PR branch, commit, or fix the code.
- Prefix each comment with "`deep-claude-code-review` (AI) on behalf of @<handle>:", where `<handle>` is the output of `gh api user --jq .login`.
- Based on the comments approved by the user, submit your review. The overall review should be a concise summary of the findings (only on the approved comments). With `--non-interactive`, submit the review the same way based on all auto-posted findings instead of an approved subset.
- Event: `COMMENT`, `REQUEST_CHANGES`, or `APPROVE` based on your review.

## Placement

Attach each comment to the exact GitHub PR diff line it is about (added, deleted, or context). Place using the PR diff (path, LEFT/RIGHT, old vs new line), never local files or local line numbers.

- If the exact line is not in the diff, put the finding in the review summary. Do not use a nearby line (docstring, Raises, helper, test, or PR description).
- If one changed line causes two issues, write one comment covering both.

## Writing

Write short human paragraphs. Explain what the line does, what is wrong, and how to fix it. Do not use labels like "What this line is", "Why it needs fixing", "How to fix", "Severity", or "Act on". Be specific (names, selectors, tests, error strings). Do not exaggerate. Keep must-fix items separate from consider items.
