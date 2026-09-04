---
name: align-docs-with-code
description: >-
  Fan a team of subagents across a project's code and its docs, find every place the docs
  contradict the code, fix the docs surgically, then tighten the prose and open a PR. Use only
  when the user runs /align-docs-with-code.
disable-model-invocation: true
user-invocable: true
argument-hint: "[--report-only] [--docs <dir>] [--ground-truth <fact>]..."
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

Record the base this run targets, always as a plain branch name such as `main`, never as a ref
path. It is the current branch when HEAD is not the repository default, so a docs pass on top of a
feature branch reviews against that feature branch rather than dragging its commits into this PR.
Otherwise it is the default branch, from `gh repo view --json defaultBranchRef --jq
.defaultBranchRef.name`, falling back to `git symbolic-ref --short refs/remotes/origin/HEAD` with
the leading `origin/` stripped. `gh pr create --base` takes a branch name and rejects
`refs/remotes/origin/main`.

Refuse if that branch is not in sync with `origin/<base>`, naming the commits that differ. GitHub
diffs the PR against the remote branch while phase 9 diffs against the local one, so an unpushed
commit on the base is invisible to phase 9 and still lands in the PR.

Everything downstream depends on this one value: phase 7 cuts the docs branch from it, phase 9
diffs against it, and phase 10 opens the PR against it and never pushes to it.

## 2. Locate the docs and the code

The doc set is `docs/` and every `*.md` beneath it, plus `README.md`, `AGENTS.md`, and `CLAUDE.md`
at the root. `--docs <dir>` replaces `docs/` when a project keeps them elsewhere. Skip anything
generated or vendored: `node_modules`, `.venv`, `site/`, `build/`, `target/`, and any directory a
site generator writes.

Find the code roots from the project's own manifests: `pyproject.toml`, `package.json`,
`Cargo.toml`, `go.mod`. **The directory containing a manifest is the root.** A monorepo has
several; record each one.

Do not narrow a root from a manifest field. PEP 621's `[project]` has no source-directory key at
all, and `package.json`'s `main` usually points at build output, so trusting either can drop a
real `src/` package from every shard and report stale docs as consistent. Treat
`[tool.setuptools]`, `[tool.hatch.build]`, and `workspaces` as hints about where to look first,
never as the boundary of what to search.

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

Each finding comes back as: the `doc-path:line`, the claim as written, the evidence, and the
smallest edit that would make it true. The evidence is normally a `code-path:line`. For a finding
that a ground-truth fact refutes, the evidence is that fact, quoted; there is no code to cite, and
such a finding is fixed in phase 7 like any other rather than dropped.

What counts as a contradiction: a named function, flag, environment variable, endpoint, or file
that does not exist or is spelled differently; a default, limit, or timeout whose value differs; a
command whose arguments have changed; a described step the code no longer performs; a claim about
what is or is not permitted that a ground-truth fact refutes.

## 6. Triage

Drop, with a line in the report:

- A finding whose real fault is in the code. Report it as a code bug and leave both alone; this
  skill does not fix code.
- A finding evidenced only by another doc.
- Deliberately aspirational prose: a roadmap, a "planned", a dated design doc describing what was
  true when written. A design doc is a record of a decision, not a description of current code.
  Check whether the doc dates or scopes itself before calling it wrong.

## 7. Fix

If triage left no survivors, stop here and go to phase 11: the docs agree with the code, which is
a result, not a failure. Cut no branch, and skip phases 8 through 10 rather than opening an empty
PR.

Create the docs branch from the base recorded in phase 1 before the first edit, so no change ever
sits on the base. Skip this under `--report-only`, which makes no edits at all.

Apply the survivors with Edit, one doc at a time. Aim for the smallest positive diff, and prefer a
net-negative one: deleting a sentence that is wrong beats rewriting it, and a claim that no longer
earns its place should go rather than be corrected.

Fix the claim, not the paragraph around it. Do not restructure a doc that is stale in one clause,
and do not reformat, reorder, or retitle anything to taste. Every hunk must trace to a phase 5
finding.

## 8. Prose pass

Load `writing-whip`, `writing-clearly-and-concisely`, `simplify-english`, and `prose-honesty`,
then re-read every hunk against all four.

`writing-whip`, `simplify-english`, and `prose-honesty` ship with this skill. The other two do
not: `writing-clearly-and-concisely` and `discernment-nudge` are third-party, installed
separately, so a plugin consumer may not have them. Load each one that is available and name any
that is missing in the report. Never skip the pass because one is absent, and never treat a
missing skill as a reason to leave prose unreviewed.

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
2. The full PR diff, not just uncommitted work: `git diff <base>...HEAD` against the base
   recorded in phase 1, plus `git diff` for anything unstaged. Every hunk traces to a phase 5
   finding, or it comes out.
3. Confirm no code file is in that diff. If one is, this run overstepped or the branch was cut
   from the wrong base: revert it and report.

## 10. Commit, push, PR

One commit per logical group, not per file. Conventional commits, imperative mood, first line 72
characters or fewer, scope `docs`.

Open the PR against the base recorded in phase 1: `gh pr create --base <base>`. The branch was
already cut from it in phase 7, so no unrelated commit rides along. Request a Copilot review if the project uses it. Never push to the
base, never merge, and never comment `@codex review`.

The PR body names each doc corrected and the evidence that proves it, the `code-path:line` or the
quoted ground-truth fact, so a reviewer can check a finding without rerunning the search. Load
`writing-whip` before writing it.

## 11. Report

In this order:

1. Docs fixed: `doc-path:line`, the claim, the evidence that disproved it.
2. Findings dropped, by which phase 6 rule.
3. Code bugs found, reported and not fixed.
4. Stale-caveat sentences left alone for want of a ground-truth fact, with their paths.
5. Docs read and found consistent, as a count and a path list.

Load `discernment-nudge` before handing back if it is installed, and say so in the report if it
is not.
