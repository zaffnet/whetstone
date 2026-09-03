---
name: align-docs-with-code
description: >-
  Fan a team of subagents across a project's code and its docs, find every place the docs
  contradict the code, fix the docs surgically, then tighten the prose and open a PR. Use only
  when the user runs /align-docs-with-code.
disable-model-invocation: true
user-invocable: true
argument-hint: "[--report-only] [--docs <dir>] [--ground-truth <fact>]..."
tools: Read Edit Write Glob Grep Bash AskUserQuestion
effort: high
metadata:
  version: "1"
---

# align-docs-with-code

Read a project's code and its docs, find every place the docs claim something the code
contradicts, fix the docs, and land the fixes as a PR. The code is the truth; this skill changes
docs, not behaviour.

Nothing here is specific to one project. Discover the docs, the code roots, and the checks from
the repository in front of you rather than assuming a layout or a language.

Terse operator mode. Report findings and paths, do not teach.

With `--report-only` in $ARGUMENTS, run phases 1 through 6 and phase 11: no branch, no edits, no
PR.

## 1. Preflight

Run `git fetch origin` first. Refuse and name the reason if the working tree is dirty, if no docs
are found in phase 2, or if `gh` is missing and `--report-only` was not passed. Uncommitted work
would be indistinguishable from this run's own change.

Resolve the base branch rather than assuming `main`: `gh repo view --json defaultBranchRef
--jq .defaultBranchRef.name`, falling back to `git symbolic-ref refs/remotes/origin/HEAD`. Do not
require HEAD to be that branch; a docs pass on top of a feature branch is legitimate. Do record
which branch this run targets, because phase 10 must never push to it.

## 2. Locate the docs and the code

The doc set is `docs/` and every `*.md` beneath it, plus `README.md`, `AGENTS.md`, and `CLAUDE.md`
at the root. `--docs <dir>` replaces `docs/` when a project keeps them elsewhere. Skip anything
generated or vendored: `node_modules`, `.venv`, `site/`, `build/`, `target/`, and any directory a
site generator writes.

Take the code roots from the project's own manifest, not from a guess: `pyproject.toml`
(`[project]`, `[tool.setuptools]`, `[tool.hatch.build]`), `package.json` (`workspaces`, `main`),
`Cargo.toml`, `go.mod`. A monorepo has several; record each one.

Stop and report if the doc set is empty. There is nothing for this skill to do.

## 3. Ground truth

A fact passed as `--ground-truth "<fact>"` outranks anything the docs say. The caller asserts it is
true now, so a doc sentence contradicting it is wrong by definition and needs no further evidence.
Record every fact before the fan-out and pass all of them to every subagent.

The case this exists for: a doc that says some access, credential, entitlement, quota, or
environment has not been granted, when the caller says it now has. Such a sentence was true when
written and silently rots. It reads as authoritative, so a reader trusts it and stops.

With no `--ground-truth`, do not guess. Collect these stale-caveat sentences as a separate class,
ask about them once with `AskUserQuestion`, and report any the caller does not resolve.

## 4. Optional graph

If the project has a `graphify-out/`, prefer `graphify query "<question>"` over reading the
codebase file by file, and read `graphify-out/GRAPH_REPORT.md` for architecture-level claims. That
is what a project carrying the graph already asks for.

With no `graphify-out/`, use Grep and Glob. Do not run `graphify` or `/graphify`: building a graph
is a slow side effect the caller did not ask for.

## 5. Shard and fan out

Split the doc set into four to six shards by directory, balanced by total size, and launch one
subagent per shard in a single turn so they run concurrently. More agents than that produces more
report than anyone reads.

Give each subagent its shard's paths, the code roots from phase 2, the ground-truth facts from
phase 3, and this instruction: verify each claim against code, never against another doc. Two docs
repeating one wrong sentence is one finding with two sites, not corroboration.

Tell every subagent it must not edit, write, or commit anything. The fan-out reads; the main agent
writes. That is what keeps two agents off the same file.

Each finding comes back as: the `doc-path:line`, the claim as written, the `code-path:line` that
contradicts it, and the smallest edit that would make it true.

What counts as a contradiction: a named function, flag, environment variable, endpoint, or file
that does not exist or is spelled differently; a default, limit, or timeout whose value differs; a
command whose arguments have changed; a described step the code no longer performs; a claim about
what is or is not permitted that a ground-truth fact refutes.

## 6. Triage

Drop, with a line in the report:

- A finding whose real fault is in the code. Report it as a code bug and leave both alone; this
  skill does not fix code.
- A finding evidenced only by another doc.
- A contradiction a ground-truth fact already settles.
- Deliberately aspirational prose: a roadmap, a "planned", a dated design doc describing what was
  true when written. A design doc is a record of a decision, not a description of current code.
  Check whether the doc dates or scopes itself before calling it wrong.

## 7. Fix

Apply the survivors with Edit, one doc at a time. Aim for the smallest positive diff, and prefer a
net-negative one: deleting a sentence that is wrong beats rewriting it, and a claim that no longer
earns its place should go rather than be corrected.

Fix the claim, not the paragraph around it. Do not restructure a doc that is stale in one clause,
and do not reformat, reorder, or retitle anything to taste. Every hunk must trace to a phase 5
finding.

## 8. Prose pass

Load `writing-whip`, `writing-clearly-and-concisely`, `simplify-english`, and `prose-honesty`, then
re-read every hunk against all four. None is optional.

Only for a doc that is a design doc, also apply
<https://refactoringenglish.com/excerpts/write-an-effective-design-doc/>: lead with the problem,
state the decision and the alternatives rejected, cut background the reader does not need. A
reference page, a runbook, or a README is not a design doc; do not reshape one to fit.

The prose pass may only shorten what phase 7 touched. It is not licence to rewrite a doc this run
had no finding against.

## 9. Verify

Discover the project's checks; do not assume they exist. In order, stopping at the first failure:

1. Whatever the repo runs itself: a `lint` recipe in a `justfile`, `Makefile`, or `package.json`,
   or `pre-commit run --all-files` when `.pre-commit-config.yaml` is present. Fix the cause, never
   suppress the checker.
2. `git diff` in full. Every hunk traces to a phase 5 finding, or it comes out.
3. Confirm no code file is in the diff. If one is, this run overstepped: revert it and report.

## 10. Commit, push, PR

One commit per logical group, not per file. Conventional commits, imperative mood, first line 72
characters or fewer, scope `docs`.

Push the branch and open the PR with `gh pr create`. Request a Copilot review if the project uses
it. Never push to the base branch recorded in phase 1, never merge, and never comment
`@codex review`.

The PR body names each doc corrected and the code that proves it, so a reviewer can check a
finding without rerunning the search. Load `writing-whip` before writing it.

## 11. Report

In this order:

1. Docs fixed: `doc-path:line`, the claim, the `code-path:line` that disproved it.
2. Findings dropped, by which phase 6 rule.
3. Code bugs found, reported and not fixed.
4. Stale-caveat sentences left alone for want of a ground-truth fact, with their paths.
5. Docs read and found consistent, as a count and a path list.

Load `discernment-nudge` before handing back.
