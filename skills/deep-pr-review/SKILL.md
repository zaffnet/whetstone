---
name: deep-pr-review
description: >-
  Multi-model code review: one independent reviewer per model you can reach (OpenAI, Anthropic, Google, ...), findings merged by agreement. Reviews a GitHub PR URL and posts inline comments after per-comment confirmation, or, with no PR, reviews the current branch or working tree and writes deep-review.local.md. Use only when the user asks for a deep or multi-model review or runs /deep-pr-review.

disable-model-invocation: true
user-invocable: true
metadata:
  version: "2"
---

# Deep PR Review

1. Parse the GitHub PR URL from the user message, if any. Use the models they named; otherwise pick the strongest model from each provider you can reach (for example one OpenAI, one Anthropic, one Google model) so the reviews are independent.
2. Launch one independent review per reviewer in parallel (host Task/subagent). Each reviewer returns findings tagged by the following severity tags: `act on`, `consider`, `noted`, or `dismissed`.
3. If two or more reviewers agree on a finding, merge them into a single finding and record the agreement count.
4. Sort the findings by severity (`act-on` > `consider` > `noted` > `dismissed`) and by the number of reviewers that agree on it.
5. Each finding will be posted as a single comment. Don't post a comment yet.

## No PR

When the user gives no PR URL, review the current branch against `origin/main` (`git diff origin/main...HEAD`), or the whole working tree if they ask for that. Run the same reviewers and merge the same way, then write the findings to `deep-review.local.md` in the repo root (it matches `*.local.*` in `.gitignore`) instead of posting anything. Use the same severity tags and the same writing rules; cite `path:line`.

## Post

- Inline review comments only after showing them to the user and asking for confirmation. Show comments one by one, i.e., show a comment, ask for confirmation, show the next comment, and so on.
- Do not edit the PR branch, commit, or fix the code.
- Prefix each comment with "`deep-pr-review` (AI) on behalf of @<handle>:", where `<handle>` is the output of `gh api user --jq .login`.
- Based on the comments approved by the user, submit your review. The overall review should be a concise summary of the findings (only on the approved comments).
- Event: `COMMENT`, `REQUEST_CHANGES`, or `APPROVE` based on your review.

## Placement

Attach each comment to the exact GitHub PR diff line it is about (added, deleted, or context). Place using the PR diff (path, LEFT/RIGHT, old vs new line), never local files or local line numbers.

- If the exact line is not in the diff, put the finding in the review summary. Do not use a nearby line (docstring, Raises, helper, test, or PR description).
- If one changed line causes two issues, write one comment covering both.

## Writing

Write short human paragraphs. Explain what the line does, what is wrong, and how to fix it. Do not use labels like "What this line is", "Why it needs fixing", "How to fix", "Severity", or "Act on". Be specific (names, selectors, tests, error strings). Do not exaggerate. Keep must-fix items separate from consider items.
