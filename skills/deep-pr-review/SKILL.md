---
name: deep-pr-review
description: "Multi-agent code review: spawns several independent agents to review a pull request, merge their findings, and post inline comments."
disable-model-invocation: true
user-invocable: true
argument-hint: "[--non-interactive] [<pr-url>]"
metadata:
  version: "3"
---

# Deep PR Review

1. Parse the GitHub PR URL from the user message, if any. Use the models they named;
   otherwise pick a few strong models from available providers so the reviews are independent.
2. Launch one independent review agent per reviewer in parallel (host Task/subagent). Each
   reviewer returns findings tagged by one of these severity tags: `act on`, `consider`,
   `noted`, or `dismissed`.
3. If two or more reviewers agree on a finding, merge them into a single finding and
   record the agreement count.
4. Sort the findings by severity (`act-on` > `consider` > `noted` > `dismissed`) and by
   the number of reviewers that agree on it.
5. Each finding will be posted as a single comment. Don't post a comment yet.

## No PR

When the user gives no PR URL, review the current branch against `origin/main`
(`git diff origin/main...HEAD`), or the whole working tree if they ask for that. Run the
same reviewers and merge the same way, then write the findings to `deep-review.local.md` in
the repo root instead of posting anything. Use the same severity tags and the same writing rules;
cite `path:line`.

## Post

- Inline review comments only after showing them to the user and asking for confirmation,
  unless `--non-interactive` was passed. In that case skip confirmation and post every
  `act on` and `consider` finding directly. In interactive mode, show comments one at a
  time: show a comment, ask for confirmation, then show the next.
- If the comment risks being cut off by the AskUserQuestion prompt, put the comment inside
  the question so the user can read it. Include its severity, the reviewers that flagged
  it, and any other relevant metadata.
- In both modes, never post `noted` or `dismissed` findings as comments.
- Do not edit the PR branch, commit, or fix the code.
- Prefix each comment with "`deep-pr-review` (AI) on behalf of @<handle>:", where
  `<handle>` is the output of `gh api user --jq .login`.
- Submit your review from the comments the user approved. The overall review is a concise
  summary of those findings only. With `--non-interactive`, submit the same way from all
  auto-posted findings instead of an approved subset.
- Event: `COMMENT`, `REQUEST_CHANGES`, or `APPROVE` based on your review.

## Placement

Attach each comment to the exact GitHub PR diff line it is about (added, deleted, or
context). Place using the PR diff (path, LEFT/RIGHT, old vs new line), never local files or
local line numbers.

- If the exact line is not in the diff, put the finding in the review summary. Do not use
  a nearby line (docstring, Raises, helper, test, or PR description).
- If one changed line causes two issues, write one comment covering both.

## Writing

Write short human paragraphs. Explain what the line does, what is wrong, and how to fix
it. Do not use labels like "What this line is", "Why it needs fixing", "How to fix",
"Severity", or "Act on". Be specific (names, selectors, tests, error strings). Do not
exaggerate. Keep must-fix items separate from consider items. Before posting any comment
or the overall review, run @"prose-honesty-auditor (agent)" and @"code-honesty-auditor (agent)"
over it and delete what they suggest. Take all their suggestions. Also, run the following skills on
the comment or the overall review: /simplify-english, /writing-whip,
/writing-clearly-and-concisely, and /prose-honesty.
