# Git & Small PRs Cheat Sheet

## PR Size Rules

- Target **< 200 changed lines**, hard ceiling ~400. Beyond that, reviewers skim
  and rubber-stamp.
- Real unit: **one logical change per PR** (one fix, one refactor, one layer).
  Line count is a proxy.
- Exempt from line limits: docs/prose, lockfiles, generated code, test fixtures,
  vendored deps. Call these out in the PR description.
- Split greenfield code **by layer**, not by file: skeleton → transport → core
  methods → extras. Each PR complete and tested on its own.

## Prevention Checklist (do this from day one)

1. Before coding, write the PR list ("this task = 3 PRs: models, transport,
   endpoints").
2. Commit at logical boundaries with real messages. Use `git add -p` to keep
   commits clean.
3. Open PR 1 before the feature is done. Review overlaps with dev.
4. Watch size: `git diff main --stat`. At ~300 lines, cut a PR now.
5. Update branches ONE way: local rebase OR GitHub's "Update branch" button.
   Never mix on the same branch.
6. Push rejected? `git fetch` and look (`git log --oneline HEAD..origin/branch`)
   BEFORE any force-push.

## Core Mental Model

- **Commit** = snapshot + pointer to parent. Named by SHA.
- **Branch** = a 41-byte file containing a SHA. "Moving a branch" = rewriting
  that file.
- **HEAD** = what you have checked out (usually points at a branch).
- **origin** = default name for the remote you cloned from. Nothing special.
- **origin/main** = your local _cached_ copy of the server's main. Stale until
  you fetch.
- **fetch** = download + update `origin/*`. Always safe. **pull** = fetch +
  merge (or rebase) into your branch.
- Rebase replays commits in **parent-chain order**, never by timestamp.
- History is never interleaved: your commits go **on top of** the target, as a
  block.

## Direction Cheat Sheet (what moves)

| Command               | What changes                               | What's untouched |
| --------------------- | ------------------------------------------ | ---------------- |
| `git rebase target`   | YOUR current branch (re-planted on target) | target           |
| `git merge other`     | your current branch (gets merge commit)    | other            |
| `git cherry-pick sha` | your current branch (copy applied)         | source           |
| `git pull`            | your current branch                        | server           |

Rule: the branch you're standing on changes. Arguments never change.

## Ours vs Theirs (it flips!)

| Operation   | ours (HEAD)                | theirs               |
| ----------- | -------------------------- | -------------------- |
| merge       | your branch                | incoming branch      |
| **rebase**  | **the target (e.g. main)** | **your own commits** |
| cherry-pick | your branch                | picked commit        |

During a rebase conflict, `<<<<<<< HEAD` is MAIN's code; `>>>>>>>` is YOURS.
Avoid `--ours`/`--theirs` shortcuts during rebase; read the markers instead.

## Stacked PRs

```bash
git switch -c pr2            # branch off pr1
# ... work ...
# open PR 2 with base = pr1 (not main)
```

- PR merged cleanly + branch deleted → GitHub auto-retargets the next PR. Do
  nothing.
- Lower PR changed during review → `git switch pr3 && git rebase pr2`. Rebase up
  the chain.
- **Main moved** → rebase ONLY from the tip:

```bash
git fetch
git switch pr3               # tip of stack
git rebase origin/main --update-refs   # git 2.38+, moves all stack refs in one pass
git push --force-with-lease origin pr1 pr2 pr3   # push EVERY branch
```

- Never rebase each stacked branch onto main separately (flattens the stack).
- `--update-refs` skips branches checked out in other worktrees. Free them
  first.
- Rebase success ≠ working code (renames slip through silently). **Run tests
  after every rebase.**

## Conflicted Rebase Procedure

```bash
# rebase pauses on conflict
# edit the file (mix both sides as needed)
git add <file>
git rebase --continue        # NOT git commit
# repeat per conflicting commit
git rebase --abort           # panic button, always works, full undo
git rebase --skip            # rare: drop this commit (main already has it)
```

Done when `git status` says "nothing to commit" on your branch. Then: test →
force-push.

## Carving a Big Branch into a Stack

```bash
git fetch
git rebase -i origin/main
```

Todo list: **top line = oldest = replayed first**. Line above becomes the
parent.

- `pick` keep · `squash`/`s` melt into line above (keep msg) · `fixup`/`f` same,
  drop msg
- `reword` edit message · `edit` pause here · `drop` remove · reorder lines =
  reorder commits
- Reordering risks conflicts (a commit's diff carries context lines from its
  original position). Squashing adjacent commits never adds conflict surface.

Splitting one commit into two (mark it `edit`, then when paused):

```bash
git reset HEAD^              # un-commit; changes back as unstaged
git add -p                   # stage hunk by hunk: y/n/s(plit)/e(dit)/q
git commit -m "layer 1"
git add . && git commit -m "layer 2"
git rebase --continue
```

Plant branches at the clean commits:

```bash
git log --oneline
git branch pr1 <sha-c1>
git branch pr2 <sha-c2>
git branch pr3               # current tip
git push origin pr1 pr2 pr3
# PR1 → main, PR2 → pr1, PR3 → pr2
```

## switch / restore (use instead of checkout)

```bash
git switch main              # move to branch
git switch -                 # previous branch
git switch -c new            # create + switch  (old: checkout -b)
git switch -c new <sha>      # create at commit
git switch --detach <sha>    # detached HEAD, explicit on purpose

git restore file             # discard working-dir changes (UNRECOVERABLE)
git restore --staged file    # un-stage, keep edits  (old: reset HEAD file)
git restore --source=main file   # grab main's version of a file
git restore -p file          # discard hunk by hunk
```

## reset Modes (moves the branch pointer, then wipes N layers)

| Mode                | Pointer | Index       | Working dir | Use for                                         |
| ------------------- | ------- | ----------- | ----------- | ----------------------------------------------- |
| `--soft`            | moves   | kept staged | untouched   | quick squash: `reset --soft HEAD~3` then commit |
| `--mixed` (default) | moves   | reset       | untouched   | un-commit: `reset HEAD^`                        |
| `--hard`            | moves   | reset       | **reset**   | discard commits / recover via reflog            |

- `reset` = local history surgery (commits only you have)
- `revert <sha>` = NEW commit that undoes an old one. The only safe undo on
  shared branches.
- `restore` = files only, never moves history.

## Recovery

```bash
git reflog                       # every HEAD move, ~90 days
git reset --hard HEAD@{1}        # undo my last history operation (reset/rebase/merge)
git reset --hard <sha>           # jump to any reflog entry
git fsck --lost-found            # last resort: dig out staged-but-never-committed blobs
```

- Committed work: always recoverable via reflog.
- Uncommitted + never staged work lost to `--hard` or `restore`: gone forever.
  Check `git status` first.

## Push Rules

```bash
git push                             # after merges / normal commits
git push --force-with-lease          # ONLY after intentional rewrites (rebase, amend, reset)
```

- Never bare `--force`. `--force-with-lease` refuses if someone else pushed to
  the branch.
- Push rejected without you rewriting anything = server has commits you lack.
  Fetch, inspect, `git pull`, then push. No force.
- Merging main into your branch needs a plain push (merge only adds; no rewrite
  happened).

## Merge vs Rebase for Updating a Feature Branch

- **Merge main in**: no rewrites, no force-push, one conflict session. Noisier
  history.
- **Rebase onto main**: linear history, per-commit conflicts, needs force-push.
- Both fine. Follow team convention. Don't mix on one branch.

## Learning Resources

1. learngitbranching.js.org (interactive, visual, do first)
2. Pro Git, free at git-scm.com/book (Ch 1-3, 5, 7.6-7.7, 10)
3. "Git from the Bottom Up" by John Wiegley (internals, short)
4. "The Git Parable" by Tom Preston-Werner (essay, 20 min)
5. ohmygit.org (game, extra reps)
