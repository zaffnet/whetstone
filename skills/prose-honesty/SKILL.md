---
name: prose-honesty
description: >-
  Judge every sentence a coding agent writes that is not language syntax --
  comments, docstrings, READMEs, design docs, ADRs, PR and commit bodies -- against
  one bar: does a reader who arrives next year, having never seen this change, need
  it? Load before writing or editing any such text, and re-check the output against
  it before handing back.
user-invocable: true
---

# Prose honesty

Your unit of judgment is not the file and not the paragraph: it is every sentence,
clause, and phrase. For each one, answer:

**Does a reader who opens this next year, having never seen this change, need it to
do their work?**

Only a clear yes survives. Set the bar high, and when a part is arguable, cut it.

**Aim for the largest honest net reduction.** Twenty lines of prose where three
would do has seventeen lines to cut. Trimming a long passage to its one load-bearing
clause counts; so does deleting it outright when no clause is load-bearing.

Everything below is how to apply the rule, not a list of words to match. Judge the
text against the thing it describes.

## The three tests

Take each sentence, and each independent clause within it, and ask:

*Could the reader derive this from the artefact itself?* Then it spends their
attention for nothing, whether it paraphrases the code below it, re-spells a name,
documents parameters a typed signature already declares, restates the heading it
sits under, or labels a section without asserting anything about it.

*Is this addressed to the reader, or to the review?* See below.

*If this clause were deleted, would the reader be unable to do something?* If they
would manage, delete it. This catches the plausible middle: the restatement of a
point already made, the sentence that sets up another sentence, the reassurance that
the thing works, the definition of a term the reader knows, the hedge, the aside,
the second example.

Also cut: decoration carrying no claim, including banners, dividers, block-end
markers, and emoji; praise nothing can verify; and a TODO naming neither the work
nor a tracking issue.

## Changelog narration

Text about how the thing came to be -- what it used to do, what changed, who asked,
what was tried, how many attempts it took -- answers a question the reader is not
holding. **They have the file, not the diff.**

No "this replaced ...", no "previously ...", no "not just the two that used to be
compared", no "four rounds of patching ... were not". This applies to READMEs,
docstrings, and design docs exactly as it applies to comments.

The constraint that a past bug revealed is worth keeping. The story of finding it is
not. Keep "the env var is the bare host, the config carries the `/v1` suffix"; cut
the account of the three stale copies that led there.

## Duplication across files

One fact, one owner, a cross-reference everywhere else. A copy is not free: copies
drift, and a reader who finds two statements of the same rule cannot tell which is
current.

Before writing a paragraph, check whether the fact already has a home. If it does,
link to it. If two files already state it, decide which one owns it and cut the
other down to a pointer. Prefer the owner the reader reaches first, or the one that
travels furthest.

## Suppressions

Report every checker suppression, in any language and any spelling: `# noqa`,
`# type: ignore`, `eslint-disable`, `shellcheck disable`, `markdownlint-disable`,
`nolint`, and their kin. This is a rule rather than a judgment: a suppression settles
nothing, so the finding behind it is still owed. **An explained suppression is a
documented unfixed defect.**

Ask for the suppression to be removed and the finding fixed. Never ask for a
narrower code or a better explanation: that leaves the defect in place and reads as
permission to keep it.

A directive that constrains more tightly than the default is not a suppression. Read
it and decide which way it points.

## Prompts are a special case

In a `SKILL.md`, an agent brief, or a rules file, the reader is a model, enumeration
*is* the mechanism, and precision beats brevity. A checklist works because it is
exhaustive; cutting it to its strongest entries makes the rest unenforced.

"Arguable, so cut" is the wrong default here. Cut a prompt only for genuine
duplication within the file, or for motivational padding that carries no
instruction. Never trade a named case for a shorter file.

## Boundaries

**A passage that is partly useful is not useful as written.** When one clause earns
its place and the rest does not, keep that clause and cut the remainder. Never let a
single good sentence carry a paragraph of padding.

**Never cut:** licence and copyright headers, shebangs, encoding declarations,
generated files, text a tool requires, a worked example the reader would otherwise
have to reconstruct, or the one sentence naming a non-obvious constraint.

**When the call is close, leave it.** You are one reader's opinion, and being wrong
here costs more than staying quiet.

## Output

Apply the cuts directly when you are editing. When you are reviewing someone else's
text, report them as a list: the file, the line, the text you object to, and what to
do with it.
