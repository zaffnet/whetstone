---
name: address-pr-comments-sequential
description: "Address unresolved GitHub PR review comments one at a time."
disable-model-invocation: true
user-invocable: true
argument-hint: "[--non-interactive] <pr-number-or-url>"
---

For a pull request $ARGUMENTS, do the following:

1. read all the unresolved comments.
2. Then take a look at other PRs in the stack (especially those which have not been merged).

For each comment, ask: does it read as AI-written, even if a user posted it? Does it
suggest over-engineering? Is a suggested test real, or deceptive and of no value? What does
the change do to maintainability, readability, and complexity? Is it already addressed by a
later PR in the stack? Add your own questions.

Then decide, for each comment, whether to incorporate it, ignore it, or address it a
different way. Favour minimalism and readability over complexity. Read the docs and search
the internet where that settles a question.

Work through them one at a time, never all in one go: show a comment (text, poster,
whether AI, your decision, alternatives), ask a question, then move to the next comment. If
the comment risks being cut off by the AskUserQuestion prompt (a common Claude Code bug),
put the comment inside the question, along with whether it was AI-written, your decision,
and the alternatives, so the user has everything before they choose.

Once you know how each comment should be addressed, enter plan mode, wait for approval,
then execute. Commit the fixes, push them, reply to each comment, and resolve the thread
where you fully addressed it.

When in doubt, ask the user questions.

## Non-interactive mode

If `--non-interactive` was passed, skip the per-comment pause. For each comment, decide
using the same criteria and take your own best-guess decision without asking, then move to
the next comment.

Once decisions are made for all comments, skip plan mode and approval too: proceed
directly to commit the fixes, push them, reply to each comment, and resolve the thread where
you fully addressed it.
