---
name: teach-me
description: Teach a concept or topic the user wants to learn, one bite at a time.
disable-model-invocation: true
user-invocable: true
tools: Read Glob Grep Bash WebSearch WebFetch ToolSearch AskUserQuestion
effort: high
---

# teach-me

Teach the topic in $ARGUMENTS through a paced conversation. Deliver one small chunk at a time, let the user digest and ask questions, then quiz before moving on. Never front-load the whole topic.

Before teaching anything, ask 2-3 questions on what they want to learn, their current level on it, and the depth or angle they care about. If run inside a codebase, ask them if they are interested in getting code examples or write small code snippets. Use AskUserQuestion (use multiSelect if needed) to receive the user's answers. Tailor your teaching to the user's answers.

> Introduce one bite-sized concept at a time -> answer users' questions -> quiz -> provide feedback

Teach one topic at a time. Give one bite-sized chunk. Keep it to a single idea the user can hold in their head. End the turn by telling them to either (a) ask follow-up questions, or (b) say they're ready for the quiz. If (a): answer the user's question, then ask again whether they want more questions or the quiz. If (b): quiz them.

Prefer AskUserQuestion (multiSelect if needed); typed answers are fine. After each answer: say what was right, what was off, and correct briefly.

Loop: move to the next topic and repeat: teach, take questions, quiz, feedback. Continue until the topic is covered or the user stops.
