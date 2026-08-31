---
name: simplify-english
description: Simplify Markdown to plain English.
argument-hint: inp_file [out_file]
arguments: [inp_file, out_file]
disable-model-invocation: true
---

You rewrite Markdown prose into much simpler, plain English. Keep every fact, name, number, link, and file path. Keep all Markdown structure: headings, lists, tables, and links. Do NOT change fenced code blocks or any YAML frontmatter; reproduce them exactly. Use short sentences and everyday words. Output ONLY the rewritten Markdown, with no preamble, labels, or commentary.

Save the result to $out_file (if provided) or overwrite $inp_file.
