---
name: deep-pr-review
description:
  "Multi-agent code review: spawns several independent agents to review a pull request, merge their
  findings, and post inline comments."
disable-model-invocation: true
user-invocable: true
argument-hint: "[--non-interactive] [<pr-url>]"
metadata:
  version: "4"
---

# Deep PR Review

1. Parse the GitHub PR URL from the user message, if any. Pick a few strong, different models
   from the available models or providers, so the reviews are independent. If only one provider is
   available, pick a few strong models from that provider instead. Pick no more than three models.

2. Launch one independent reviewer agent per model, in parallel (host Task/subagent). Give each
   agent the instructions from the section `Reviewer Instructions`.

3. Each reviewer returns findings tagged with one of these labels and decorators. Labels: `praise`,
   `nitpick`, `suggestion`, `issue`, `todo`, `question`, `thought`, `chore`, `note`. Decorators:
   `(non-blocking)`, `(blocking)`, `(if-minor)`.

4. If two or more reviewers agree on a finding, merge them into one finding and record how many
   agree. Two agents may flag the same finding with different labels or decorators. When you merge,
   pick the label and decorator that fits best.

5. Each finding will become one comment. Don't post any comment yet.

## No PR

If the user gives no PR URL, review the current branch against `origin/main`
(`git diff origin/main...HEAD`), or the whole working tree if they ask for that. Run the same
reviewers and merge the same way, then write the findings to `deep-review.local.md` in the repo root
instead of posting anything. Use the same labels, decorators, and writing rules; cite `path:line`.

## Format

```text
<label> [decorators]: <subject>

[discussion]
```

- label - A single label for what kind of comment this is.

- subject - The main message of the comment.

- decorators (optional) - In parentheses, comma-separated.

- discussion (optional) - Supporting statements, context, reasoning, and anything else that explains
  the "why" and the "next steps" for resolving the comment.

### Labels

- `praise`: Praises highlight something positive. Don't leave false praise. Do look for something to
  sincerely praise.

- `nitpick`: Nitpicks are trivial, preference-based requests. These are always non-blocking.

- `suggestion`: Suggestions propose improvements to the subject. Consider using patches and the
  blocking or non-blocking decorators to make your intent clearer.

- `issue`: Issues highlight specific problems with the subject under review. These problems can be
  user-facing or behind the scenes. Pair this comment with a suggestion. If you're not sure a
  problem exists, leave a question instead.

- `todo`: TODOs are small, trivial, but necessary changes. Distinguish them from issue or suggestion
  comments, so the reader knows which comments need more work.

- `question`: Use a question when you have a potential concern but you're not sure it's relevant.

- `thought`: Thoughts are ideas that came up while reviewing. These are always non-blocking.

- `chore`: Chores are simple tasks that must be done before the subject can be "officially"
  accepted. Link the process description so the reader knows how to resolve the chore.

- `note`: Notes are always non-blocking. They simply point out something the reader should know.

### Decorators

- `(non-blocking)`: A comment with this decorator should not stop the subject under review from
  being accepted.

- `(blocking)`: A comment with this decorator should stop the subject under review from being
  accepted, until it's resolved.

- `(if-minor)`: This decorator tells the author to resolve the comment only if the change ends up
  minor or trivial.

## Reviewer Instructions

### 1. Be curious

Assume a posture of genuine curiosity. Try to catch yourself before jumping to conclusions, and ask
questions instead. For example, avoid writing comments like:

```md
suggestion: This bug could be solved in the Main component. That will probably take a lot less
code.
```

Unless you're very certain (and even if you are), ask a question from a place of genuine curiosity
instead. Write this instead:

```md
question: Could we solve this in the Main component? I wonder if that would be a more
straightforward fix and require less code.
```

### 2. Be patient and kind

Share knowledge with patience and kindness.

### 3. Leave actionable comments

Make sure it's really clear how to resolve a review comment.

### 4. Combine similar comments

Batch similar issues into one comment, preferably with a patch. For example:

````md
suggestion: Could we rename all m_X variables to just X? I see we decided to use Hungarian
Notation, but that isn't followed in this project.

For example, let's do:

```typescript
interface Wizard {
  foo: string;
}
```

Instead of:

```typescript
interface Wizard {
  m_foo: string;
}
```
````

### 5. Replace "you" with "we"

For example, rather than saying:

```md
issue: You should write tests for this.
```

say:

```md
todo: We should write tests for this.
```

## Post

- Post inline review comments only after showing them to the user and asking for confirmation,
  unless `--non-interactive` was passed. With `--non-interactive`, skip confirmation and post every
  comment directly, after merging. In interactive mode, show comments one at a time: show a
  comment, ask for confirmation, then show the next.

- If the comment risks being cut off by the AskUserQuestion prompt, put the comment inside the
  question so the user can read it. Include its label and decorators, the reviewers who flagged it,
  and any other relevant details.

- Don't edit the PR branch, commit, or fix the code.

- Submit your review using the comments the user approved (in interactive mode). The overall review
  is a short summary of just those findings. With `--non-interactive`, submit the same way, but use
  all auto-posted findings instead of an approved subset.

- Event: `COMMENT`, `REQUEST_CHANGES`, or `APPROVE`, based on your review.

## Placement

Attach each comment to the exact GitHub PR diff line it's about (added, deleted, or context). Use
the PR diff to place it (path, LEFT/RIGHT, old vs. new line), never local files or local line
numbers.

- If the exact line isn't in the diff, put the finding in the review summary instead. Don't use a
  nearby line (docstring, Raises, helper, test, or PR description).
- If one changed line causes two issues, write one comment that covers both.

## Writing

Write short, human paragraphs. Explain what the line does, what's wrong, and how to fix it. Don't
use labels like "What this line is", "Why it needs fixing", "How to fix", "Severity", or "Act on".
Be specific: name the variables, selectors, tests, and error strings involved. Don't exaggerate.
Before posting any comment or the overall review, run @"prose-honesty-auditor (agent)" and
@"code-honesty-auditor (agent)" over it, and delete what they suggest. Take all their suggestions.
Also run these skills on the comment or the overall review: /simplify-english, /writing-whip,
/writing-clearly-and-concisely, and /prose-honesty.
