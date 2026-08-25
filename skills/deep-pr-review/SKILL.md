---
name: deep-pr-review
description: >-
  Runs a multi-model review of a GitHub pull request and posts a COMMENT review with inline notes on act-on and consider findings. Use only when the user explicitly asks for a deep PR review, multi-model PR review, or /deep-pr-review and provides a PR URL.

disable-model-invocation: true
metadata:
  version: "1"
---

# Deep PR Review

1. Parse the GitHub PR URL from the user message. Use the models they named; otherwise pick the strongest model from each provider you can reach (for example one OpenAI, one Anthropic, one Google model) so the reviews are independent.
2. Launch one independent review per model in parallel (host Task/subagent). Each reviewer returns findings tagged by the following severity tags: `act on`, `consider`, `noted`, or `dismissed`.
3. If two or more agents agree on a finding, merge them into a single finding.
4. Sort the findings by severity (`act-on` > `consider` > `noted` > `dismissed`) and by the number of agents that agree on it.
5. Each finding will be posted as a single comment. Don't post a comment yet.

## Post

- Inline review comments only after showing them to the user and asking for confirmation. Show comments one by one, i.e., show a comment, ask for confirmation, show the next comment, and so on.
- Do not edit the PR branch, commit, or fix the code.
- Prefix each comment with "`deep-pr-review` (AI) on behalf of @<handle>:", where `<handle>` is the output of `gh api user --jq .login`.
- Based on the comments approved by the user, submit your review. The overall review should be  a concise summary of the findings (only on the approved comments).
- Event: `COMMENT`, `REQUEST_CHANGES`, or `APPROVE` based on your review.

## Placement

Attach each comment to the exact GitHub PR diff line it is about (added, deleted, or context). Place using the PR diff (path, LEFT/RIGHT, old vs new line), never local files or local line numbers.

- If the exact line is not in the diff, put the finding in the review summary. Do not use a nearby line (docstring, Raises, helper, test, or PR description).
- If one changed line causes two issues, write one comment covering both.

## Writing

Write short human paragraphs. Explain what the line does, what is wrong, and how to fix it. Do not use labels like "What this line is", "Why it needs fixing", "How to fix", "Severity", or "Act on". Be specific (names, selectors, tests, error strings). Do not exaggerate. Keep must-fix items separate from consider items.
