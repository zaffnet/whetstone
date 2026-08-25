---
name: fix-design-implementation-discrepancies
description: Use only when the user invokes `/fix-design-implementation-discrepancies <PR number or link>`. Reviews a PR against the living design and schema docs, asks how each discrepancy should be resolved, then makes the chosen minimal fixes.
model: opus
disable-model-invocation: true
effort: high
---

# Fix Design / Implementation Discrepancies

Use this skill only for:

```text
/fix-design-implementation-discrepancies <PR number or link>
```

If the PR number or link is missing, ask for it and stop.

## Workflow

1. Read the project's living design documents end to end: the design doc, the schema doc, and the API contract. Take their paths from the project's `AGENTS.md` or `CLAUDE.md`; if neither names them, ask the user.
2. Inspect the target PR's implementation changes, including changed files and relevant discussion if available.
3. Compare the PR against all three docs and list discrepancies from highest to lowest severity. Include line references into the docs, plus PR file references when useful.
4. For each discrepancy, ask the user whether the docs/schema should change to match the PR or the PR should change to match the docs/schema. Use the available user-question tool (AskUserQuestion) when possible, and ask follow-up questions until the intended resolution is clear.
5. If the docs/schema should change, make only the minimal necessary edits. Present the original design and PR implementation as alternatives, then add a very short note explaining why the PR implementation is preferred.
6. If the PR implementation should change, ask what behavior or code should change before editing. Do not assume the implementation direction.
7. Validate the result by rereading the touched docs and checking that the final text still makes sense on its own.

All questions must be asked using AskUserQuestion.

## Living-Doc Rules

Treat the design doc, schema tables, and API contract as current reference material, not historical logs. Anyone should be able to read them later and understand the system as it exists after the PR merges while also understanding why certain design decision were made.

When editing docs:

- Do not leave references to deleted behavior, removed fields, renamed tables, or obsolete flows.
- Keep every link, table reference, heading reference, file path, and model name accurate.
- Prefer direct current-state wording over historical phrasing like "previously," "newly," or "this PR changes."
- Keep edits small and local to the discrepancy being resolved.
