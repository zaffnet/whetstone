# AGENTS.md / CLAUDE.md

## Writing Prose (documentation, comments, etc.)

Load the `writing-whip` skill before writing prose, and `prose-honesty` before writing
comments, docstrings, docs, or a PR body.

## Code style

Python follows [PEP 8](https://peps.python.org/pep-0008/) for judgment calls. Ruff
(pre-commit) owns naming, formatting, and imports.

Keep the docstrings on public modules, classes, and functions short. Use
@"code-honesty-auditor (agent)" to audit any docstrings or comments you have written in
any code.

Write the minimum that solves the problem. Keep diffs surgical: every changed line traces
to the request. Mention unrelated dead code; make a case for them to delete, and when permission is
granted, delete them. Do it routinely and religiously. Remove names that have become unused.

Fix the root cause. Do not leave `# type: ignore`, bare `except: pass`, or unexplained
`# noqa`. When a type error comes from a dependency, add real stubs -- `types-<pkg>` or a
`stubs/` entry -- rather than annotating the call site as `Any`. Reserve `Any` for values
that are genuinely dynamic.

Imports go at the top of the module, never inside a function body, a type annotation, or
an interface field. A real circular dependency is the one exception; name it next to the
import.

Do not add tests that only assert a constant or a fact ruff, mypy, or basedpyright already
prove. No section-separator comments. No template docstrings that restate the function
name.

## Code taste

Aim for the largest honest net negative diff. Reduction is the deliverable, not a side effect
of one. This applies to code, comments, docs, PR size, and tooling alike. If a change adds
lines, be able to say what those lines buy.

### Scope and diffs

- Write the minimum that solves the problem.
- Every changed line traces to the request. If it does not, it is a separate change.
- Mention dead code you find. Confirm is is no longer needed and delete it.
- Remove names this change made unused, including ones you added that turned out unused.
- Scope is a contract. Do not quietly widen or narrow it; if it must change, say so.
- Parking a decision as a "follow-up" is usually evasion. Decide it or name who will.

### Comments and docstrings

The bar: does a reader who opens this next year, having never seen the change, need it? Judge
each clause, not the file. If keeping it is arguable, cut it. Survivors state a cause, a
constraint, or a consequence the code cannot state itself.

```python
# Keep: the plural `correlationIds` is ignored upstream and would match both calls
# Cut:  Repeatable UUID filter; values may repeat   <- the type says it, twice
```

- No changelog narration. The reader has the file, not the diff.
- No banner comments, no section separators, no emoji.
- No TODO without either the work or an issue reference.
- Where a linter requires a docstring, shrink it rather than delete it.
- Never document behaviour no test exercises.
- Consistency with the surrounding file beats a marginal improvement. When the call is close,
  leave it.

### Naming

- Accurate beats short. Four words is fine.
- No metaphor that misleads about what the thing does.
- Reuse the exact word the code, the doc, or the user already used.
- A good name makes its comment redundant. Prefer the rename.
- Find every opportunity to rename. Clear names will help readers understand the code better.

### Structure and typing

- Imports at module top. A circular dependency is the only reason to move one inside.
  Avoid circular dependencies.
- Early returns over nested conditionals. Keep functions short.
- Write a real type or stub rather than `Any`.
- No suppressions, and no laundering one suppression into another form. Fix the root cause.
- Modern generics and `X | None`, not the legacy spellings.
- Model variants as a discriminated union and match exhaustively, closing with `assert_never`,
  so adding a variant is a compile error at each site that must change and nowhere else.
- A library never knows its caller: no consumer-shaped parameters, no imports pointing up.
- Data does not live inside the script that generates from it.
- Mark generated files as generated so review lands on the generator.

### Errors and logging

- A custom exception hierarchy per boundary, raised at that boundary.
- At a library boundary, sever the chain: raise the library's own error without the
  internal cause.
- Libraries log through the standard library's logging only, and configure nothing.
- Defensive checks on trusted internal paths are slop. Validate at the edge, then trust it.

### Tests

- Every test runs against the real thing. "This cannot be tested live" is nearly always a
  claim about the attempt, not about the world; change the request, the credentials, or the
  config and try again. A mock-only test needs a written reason.
- Fake data is either obviously synthetic or copied verbatim from a real response. Never
  invent data and describe it as real.
- A mock that agrees with your own misreading proves nothing.
- Mutation-test the test: break the code and confirm it fails.
- Partial verification reads exactly like proof. Say which part you checked.
- One invalid input is enough. Do not walk every field constraint.
- Do not test what the type checker or linter already proves.
- Deleting a test is legitimate. Confirm it is no longer needed and delete it liberally.
- Weigh a test against the lines it costs. Tests are code and carry the same bar.

### Verification

- Evidence before claims, always. Run the thing, then report.
- Run checkers the way the gate runs them, including with no path argument.
- Two checkers disagreeing is information, not noise. Understand it before silencing either.
- Zero findings is the bar, whether or not the hook is set to block.
- Probe the live system before claiming what it does.
- Reading a doc is not evidence. Assume the spec is wrong until the system agrees with it.
- Documents become stale. They may be inaccurate. Do not blindly trust them.
- Talk is cheap. Show me the code.

### Prose and docs

- Plain sentences stating facts and decisions. A list where the material is a list.
- Describe the current state. No history, no record of how the design was reached.
- Design docs stay out of implementation detail.
- One fact has one owner. Everywhere else cross-references it.
- Sentence case headings, straight quotes, no em dashes, no arrow glyphs.
- For work that needs judgment, use judgment. A brittle deterministic script that approximates
  a judgment call is worse than making the call.

## Writing style

- Write for humans, not agents.
- If the code, the doc, or the user already named it, use that exact word. Do not
  paraphrase a technical term, and do not coin a near-synonym or near-homophone of one.

## Stacked pull requests

Run `gh stack list` to see the stack. Use `/gh-stack` to work with GitHub Stack.

## Handing off

Report the result of each:

1. `uv run pre-commit run --all-files` passes.
2. `run-typecheck.sh` passes.
3. Run @"prose-honesty-auditor (agent)" and @"code-honesty-auditor (agent)" over every
   file the session touched, and delete what they name. Take all their suggestions.
4. Run the following skills on every file the session touched: /simplify-english,
   /writing-whip, /writing-clearly-and-concisely, and /prose-honesty.

## Git

Small PRs, one logical change each. Conventional commits, imperative mood, first line of
72 characters or fewer. Never push to `main`: push a branch, open the PR.

## Skills

Check `~/.agents/skills` at the start of a task and load the ones that match.
