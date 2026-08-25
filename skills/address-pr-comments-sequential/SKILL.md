---
name: address-pr-comments-sequential
description: >-
  Address unresolved GitHub PR review comments one at a time.


disable-model-invocation: true
user-invocable: true
argument-hint: <pr-number-or-url>
---

For a pull request $ARGUMENTS, do the following:

1. read all the unresolved comments.
2. Then take a look at other PRs in the stack (especially those which have not been merged).

Once you read all the comments, you should have a general idea on what changes need to be made. For each comment, think carefully. Is the comment coming from an AI (although posted by a user) or does it sound human and not AI? Is the comment suggesting something that is over-engineering or typical of AI reviews of pull requests? Is a suggestion of a test real or is the test that the comment wants to be added is deceptive and brings no value? What will be effects on code maintainability and readability and complexity of the software if the suggested change is incorporated. Is the comment addressed by a subsequent PR in the stack? Ask all such questions (come up with your own questions too).

Then for each comment, show the user who commented it, whether you think the comment is made by AI, the complete comment text, your own decision on whether to incorporate the changes mentioned in the comment or to ignore the comment or to address it in a different way. Think like a senior software engineer. Think like someone who values minimalism and readability and hates complexity. Think outside the box. Read the docs, search the internet, do whatever you can to provide the best software engineering experience and the most elegant code at the end. Next, provide the user alternative ways on how to address the comment by using AskUserQuestion or AskQuestion or any such tool available to you.

Do not show all comments and their resolutions in one go.

Show a comment (comment text, poster, whether AI, other metadata,your decision, other alternatives) -> Ask a question -> Next comment -> and so on. If you are afraid the comment shown will be blocked by the question asked using AskUserQuestion (common bug in Claude Code), then you should make the comment part of the question so user can read it. Along with comment, also show whether it was made by AI, your decision, alternatives, etc. so the user has all the information viewable before they make informed decision and select an option.

Once you have understood how each comment should be addressed as per the user, create a plan by entering the plan mode, wait for the user to approve it, then execute the plan. Commit the fixes, push them and reply to each comment. If you have fully addressed a comment, resolve the comment thread if possible.

When in doubt, ask the user questions.
