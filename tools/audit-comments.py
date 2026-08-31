#!/usr/bin/env python3
"""Report comments and docstrings that record a session instead of the code.

Reports only; never rewrites. A comment containing a reason is never reported:
see _WHY_MARKER.

Usage: audit-comments.py [path[:LINE,LINE,...] ...]
A path with a line list reports only findings anchored on those lines, which is
how the Stop hook limits a report to what the session actually wrote. A path
without one is read whole.
Exit status is 1 when a finding is reported, 0 when clean.
"""

from __future__ import annotations

import ast
import io
import re
import sys
import tokenize
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING

# Anchored: a leading "Changed:" is a changelog entry, while "changed"
# mid-sentence is usually prose about behaviour.
_SESSION_OPENERS = re.compile(
    r"""^(?:
        (?:new|updated?|changed?|fixed|added|removed|refactored|renamed|moved
          |improved|enhanced|cleaned\s+up|simplified|note|nb)\b\s*[:!-]
        | (?:we|i)\s+(?:now|just|also|have|had|added|changed|removed|fixed|moved)\b
        | (?:as|per)\s+(?:requested|discussed|asked|your\s+request)\b
        | (?:this|these)\s+(?:used\s+to|was|were|previously)\b
        | (?:previously|formerly|originally|instead\s+of)\b
        | (?:no\s+longer|not\s+anymore)\b
        | (?:for\s+now|temporar\w+|placeholder|stub\s+for\s+now)\b
    )""",
    re.IGNORECASE | re.VERBOSE,
)

# A divider or banner: punctuation runs, or a short all-caps label fenced by them.
_BANNER = re.compile(r"^(?:[-=*#~_+/\\ ]{6,}|[-=*#~_+]{2,}.*?[-=*#~_+]{2,})$")

# Praise a reader cannot check and a checker cannot enforce.
_MARKETING = re.compile(
    r"""\b(?:
        production[- ]ready | enterprise[- ]grade | battle[- ]tested | robust
        | comprehensive | state[- ]of[- ]the[- ]art | best[- ]practice | world[- ]class
        | blazing(?:ly)?\s+fast | fully\s+(?:tested|typed|documented)
        | carefully | elegant | clean\s+and\s+simple
    )\b""",
    re.IGNORECASE | re.VERBOSE,
)

# The pictographic blocks only. Escaped, not literal, so the ranges are legible
# in a diff. Arrows and dingbats are left out: an arrow is punctuation a comment
# may reasonably use, so flagging it would report a comment for its typography.
_EMOJI = re.compile(
    "["
    "\U0001f300-\U0001f5ff"  # symbols and pictographs
    "\U0001f600-\U0001f64f"  # emoticons
    "\U0001f680-\U0001f6ff"  # transport and map
    "\U0001f900-\U0001f9ff"  # supplemental symbols and pictographs
    "\U0001fa70-\U0001faff"  # extended-A
    "\U0001f1e6-\U0001f1ff"  # regional indicators
    "\u2705\u274c\u2757\u2b50\u2728\u2764\ufe0f"  # the common standalone marks
    "]"
)

# "Note that ...", "It is worth noting ...": filler that precedes a restatement.
_HEDGE_OPENER = re.compile(
    r"""^(?:
        note\s+that | notice\s+that | keep\s+in\s+mind | be\s+aware
        | remember\s+that | please\s+note
        | it(?:'s|\s+is)\s+(?:worth\s+noting|important\s+to\s+note)
    )\b""",
    re.IGNORECASE | re.VERBOSE,
)

# Exempts a comment from every shape-based rule below. Deliberately generous:
# a false negative leaves one noisy comment, a false positive deletes the only
# record of why the code is shaped as it is.
_WHY_MARKER = re.compile(
    r"""\b(?:
        because|since|otherwise|unless|whereas|although|though|despite|however
        | workaround|caveat|gotcha|assumes?|assumption|invariant|guarantees?
        | breaks?\s+when|fails?\s+when|crashes?\s+when|only\s+when|must|has\s+to\s+be
        | to\s+avoid|to\s+prevent|to\s+ensure|in\s+order\s+to|so\s+that|which\s+is\s+why
        | by\s+design|on\s+purpose|deliberate\w*|intentional\w*|not\s+a\s+bug
        | upstream|downstream|third[- ]party|vendor|spec|rfc|cve|protocol
        | race|deadlock|timeout|retry|retries|idempotent|thread[- ]safe|atomic
        | trade[- ]?off|expensive|hot\s+path|allocat\w+|quadratic|o\(n
        | bug|issue|ticket|see\s+(?:issue|https?://)|https?://
        | e\.g\.|i\.e\.|for\s+example
    )\b""",
    re.IGNORECASE | re.VERBOSE,
)

# `} // end if`, `# end of function`: the block already ended.
_END_MARKER = re.compile(
    r"^end(?:\s+of)?\b|^/?\*?\s*end\s+(?:if|for|while|def|class|function|method|try|loop)\b",
    re.IGNORECASE,
)

# A label with no content: "Main logic", "Helper function", "Error handling".
_EMPTY_LABEL = re.compile(
    r"""^(?:
        (?:main|core|helper|utility|util|business|application|internal|private|public)\s+
        (?:logic|code|functions?|methods?|helpers?|section|part|stuff)
        | (?:error|exception|edge\s+case)\s+handling
        | (?:imports?|constants?|globals?|types?|variables?|fields?|properties
          |setup|teardown|initialization|cleanup|configuration|config)
        | this\s+is\s+important
        | (?:begin|start|end)\s+(?:of\s+)?(?:section|block|region)
    )\s*[.:]?$""",
    re.IGNORECASE | re.VERBOSE,
)

# A TODO naming no work and no issue. One that links an issue is left alone.
_VAGUE_TODO = re.compile(
    r"""^(?:todo|fixme|hack|xxx)\b\s*[:.\-]?\s*
        (?:
            (?:implement|add|handle|fix|finish|complete|improve|refactor|clean\s*up|revisit)?
            \s*
            (?:this|that|it|here|later|properly|correctly|for\s+now|if\s+needed
              |functionality|logic|error\s+handling|edge\s+cases?|tests?)?
        )\s*[.!]?$""",
    re.IGNORECASE | re.VERBOSE,
)

# Under this share of code lines, findings read as stray comments rather than a
# narrated file. Threshold from aislop.
_MIN_DENSITY = 0.02
_ALWAYS_REPORT_AT = 4

# A body of this many statement lines or fewer needs no Args/Returns section.
_SHORT_BODY = 3
# Docstrings shorter than this are never bulk, whatever the body length.
_MIN_ESSAY_LINES = 12
# Prose over this multiple of the body it documents is bulk.
_ESSAY_RATIO = 3
# A summary and one section already fill this many lines, so sections only look
# like boilerplate past it.
_MIN_SECTIONED_DOC = 4
# Fewer significant words than this cannot establish a restatement.
_MIN_RESTATEMENT_WORDS = 2
# Words this short carry too little meaning to match on.
_MIN_WORD_LEN = 2
# A licence header sits at the top of the file.
_HEADER_LINES = 3
# Crude stemming only applies to words long enough to keep a stem.
_MIN_STEM_LEN = 3

# Section labels a docstring uses; a docstring is "structured" when it has one.
_DOC_SECTION = re.compile(
    r"""^\s*(?:
        args | arguments | parameters | params | returns? | yields? | raises?
        | attributes | examples? | notes? | see\s+also | todo | warns? | warnings?
    )\s*:\s*$""",
    re.IGNORECASE | re.MULTILINE | re.VERBOSE,
)

_STOPWORDS = frozenset(
    {
        "a",
        "an",
        "the",
        "of",
        "to",
        "for",
        "from",
        "with",
        "by",
        "on",
        "in",
        "at",
        "into",
        "over",
        "under",
        "and",
        "or",
        "is",
        "are",
        "be",
        "this",
        "that",
        "it",
        "its",
        "as",
        "if",
        "then",
        "when",
        "new",
        "get",
        "set",
        "add",
        "remove",
        "make",
        "build",
        "create",
        "return",
        "returns",
        "given",
    }
)

CODE_SUFFIXES = frozenset({".py", ".pyi"})

if TYPE_CHECKING:
    # Annotations are strings under `from __future__ import annotations`, so this
    # is never evaluated at runtime. It is written this way rather than as a 3.12
    # `type` statement because the Stop hook runs whichever python3 is on PATH.
    _Documentable = ast.Module | ast.ClassDef | ast.FunctionDef | ast.AsyncFunctionDef


@dataclass(frozen=True)
class Finding:
    path: Path
    line: int
    rule: str
    detail: str
    # Last line the finding covers. A comment is one line; a docstring is as
    # many as it spans, so editing any line of one puts the whole in scope.
    end_line: int = 0

    @property
    def span(self) -> range:
        return range(self.line, max(self.end_line, self.line) + 1)

    def __str__(self) -> str:
        return f"  {self.path}:{self.line}  {self.rule}: {self.detail}"


def _words(text: str) -> list[str]:
    return re.findall(r"[a-z0-9]+", text.lower())


def _significant(text: str) -> list[str]:
    return [w for w in _words(text) if w not in _STOPWORDS]


def _first_sentence(doc: str) -> str:
    stripped = doc.strip()
    head = re.split(r"(?<=[.!?])\s|\n\s*\n", stripped, maxsplit=1)[0]
    return head.strip()


def _restates_name(name: str, summary: str) -> bool:
    """Say whether a docstring's summary only repeats the name.

    ``def get_user(...)`` documented as "Get the user." carries nothing. Set-based
    so "Gets user" and "Returns the user" both count. A summary adding any word
    the name lacks is left alone: that word is where the information would be.
    """
    name_parts = _significant(re.sub(r"(?<!^)(?=[A-Z])", " ", name.replace("_", " ")))
    summary_parts = _significant(summary.rstrip(".").strip())
    if len(name_parts) == 0 or len(summary_parts) == 0:
        return False

    def stem(word: str) -> str:
        for suffix in ("ies", "es", "s"):
            if len(word) > _MIN_STEM_LEN and word.endswith(suffix):
                return word[: -len(suffix)] + ("y" if suffix == "ies" else "")
        return word

    return {stem(w) for w in summary_parts} <= {stem(w) for w in name_parts}


def _code_of_line(lines: list[str], lineno: int) -> str:
    """Return a line's code with its trailing comment and string bodies removed."""
    raw = lines[lineno - 1] if 0 < lineno <= len(lines) else ""
    without_strings = re.sub(r"(['\"]).*?\1", "", raw)
    return without_strings.split("#", 1)[0].strip()


def _restates_code(comment: str, code: str) -> bool:
    """Say whether a comment's words are a subset of what the code already says.

    ``counter += 1  # increment counter`` restates. Operators count as the words
    they are read aloud as, otherwise punctuation hides the commonest cases.
    """
    spoken = {
        "+=": ("increment", "increase", "add", "bump"),
        "-=": ("decrement", "decrease", "subtract"),
        "*=": ("multiply", "scale"),
        "/=": ("divide",),
        "=": ("set", "assign", "store", "initialize", "initialise"),
        "==": ("compare", "check", "equal", "equals"),
        "+": ("add", "sum", "concatenate"),
        "-": ("subtract",),
        "%": ("modulo", "remainder"),
        "[": ("index", "lookup", "element", "item"),
    }
    code_words = {w for w in _significant(code) if len(w) > _MIN_WORD_LEN}
    for symbol, words in spoken.items():
        if symbol in code:
            code_words.update(words)

    comment_words = {w for w in _significant(comment) if len(w) > _MIN_WORD_LEN}
    if len(comment_words) < _MIN_RESTATEMENT_WORDS or len(code_words) == 0:
        return False
    return comment_words <= code_words


# Machine-read, not prose. The typecheck hook owns these.
_PRAGMA = re.compile(r"^(?:noqa|type:|pyright:|pyrefly:|mypy:|ruff:|fmt:|isort:)")
_FILE_HEADER = re.compile(r"copyright|spdx|licen[sc]e|-\*-|!/", re.IGNORECASE)

# Checked in order. The two before _WHY_MARKER are pure noise that a stated
# reason does not excuse; every rule after it guesses from wording, so a comment
# carrying a reason is left alone.
_NOISE_RULES: tuple[tuple[re.Pattern[str], str, str], ...] = (
    (_EMOJI, "emoji", "{short}"),
    (_MARKETING, "marketing", "unverifiable praise: {short}"),
)
_SHAPE_RULES: tuple[tuple[re.Pattern[str], str, str], ...] = (
    (_BANNER, "banner", "section separator comment"),
    (_END_MARKER, "end-marker", "the block already ends: {brief}"),
    (_EMPTY_LABEL, "empty-label", "names a category, not a fact: {brief}"),
    (_VAGUE_TODO, "vague-todo", "no work and no issue named: {brief}"),
    (_SESSION_OPENERS, "session-narration", "reports the edit: {short}"),
    (_HEDGE_OPENER, "hedge", "filler opener: {short}"),
)


def _match_rules(
    rules: tuple[tuple[re.Pattern[str], str, str], ...], raw: str
) -> tuple[str, str] | None:
    for pattern, rule, template in rules:
        if pattern.search(raw) is not None:
            return rule, template.format(short=repr(raw[:60]), brief=repr(raw[:40]))
    return None


def _comment_finding(path: Path, line: int, raw: str, lines: list[str]) -> Finding | None:
    if _PRAGMA.match(raw) is not None or (
        line <= _HEADER_LINES and _FILE_HEADER.search(raw) is not None
    ):
        return None

    if (hit := _match_rules(_NOISE_RULES, raw)) is not None:
        return Finding(path, line, hit[0], hit[1])
    if _WHY_MARKER.search(raw) is not None:
        return None
    if (hit := _match_rules(_SHAPE_RULES, raw)) is not None:
        return Finding(path, line, hit[0], hit[1])

    # An own-line comment describes the line below it; a trailing one its own.
    code = _code_of_line(lines, line)
    target = code if code != "" else _code_of_line(lines, line + 1)
    if target != "" and _restates_code(raw, target):
        return Finding(path, line, "restates-code", repr(raw[:60]))
    return None


def audit_comments(path: Path, source: str) -> list[Finding]:
    lines = source.splitlines()
    try:
        tokens = list(tokenize.generate_tokens(io.StringIO(source).readline))
    except (tokenize.TokenError, IndentationError, SyntaxError):
        return []

    findings: list[Finding] = []
    for token in tokens:
        if token.type != tokenize.COMMENT:
            continue
        raw = token.string.lstrip("#").strip()
        if raw == "":
            continue
        if (finding := _comment_finding(path, token.start[0], raw, lines)) is not None:
            findings.append(finding)
    return findings


def _docstring_targets(tree: ast.Module) -> list[tuple[str, _Documentable]]:
    targets: list[tuple[str, _Documentable]] = [("<module>", tree)]
    targets.extend(
        (node.name, node)
        for node in ast.walk(tree)
        if isinstance(node, ast.ClassDef | ast.FunctionDef | ast.AsyncFunctionDef)
    )
    return targets


def _body_span(node: _Documentable) -> int:
    """Count statement lines in a function body, or return -1 when not a function."""
    if not isinstance(node, ast.FunctionDef | ast.AsyncFunctionDef):
        return -1
    body = node.body
    if len(body) > 0 and isinstance(body[0], ast.Expr) and isinstance(body[0].value, ast.Constant):
        body = body[1:]
    if len(body) == 0:
        return 0
    first, last = body[0], body[-1]
    # end_lineno is Optional on every ast node, and None on a node the parser
    # did not position, so the start line is the floor.
    end = last.end_lineno
    return (end if end is not None else last.lineno) - first.lineno + 1


def _docstring_prose_rule(name: str, doc: str) -> tuple[str, str] | None:
    """Name the rule a docstring's prose breaks, or None when it breaks none."""
    if _EMOJI.search(doc) is not None:
        return "emoji", f"docstring for {name}"
    if (marketing := _MARKETING.search(doc)) is not None:
        return "marketing", f"{name}: unverifiable praise {marketing.group(0)!r}"
    if (session := _SESSION_OPENERS.search(doc)) is not None:
        return (
            "session-narration",
            f"{name}: docstring reports the edit ({session.group(0).strip()!r})",
        )
    if name != "<module>" and _restates_name(name, _first_sentence(doc)):
        return "restates-name", f"{name}: summary re-spells the name"
    return None


def _docstring_rule(name: str, doc: str, span: int) -> tuple[str, str] | None:
    """Name the rule a docstring breaks, or None when it breaks none."""
    if (hit := _docstring_prose_rule(name, doc)) is not None:
        return hit

    doc_lines = len(doc.splitlines())
    # A short body does not need Args/Returns; the signature is right there, and
    # the handbook says one-line helpers skip those sections. Sections restating
    # a typed signature are boilerplate whatever else the docstring says, so this
    # runs ahead of the why-marker check below.
    if (
        0 <= span <= _SHORT_BODY
        and _DOC_SECTION.search(doc) is not None
        and doc_lines > _MIN_SECTIONED_DOC
    ):
        return (
            "oversized-docstring",
            f"{name}: {doc_lines}-line docstring with sections over a {span}-line body",
        )
    # Prose far longer than the code it documents is where session essays land,
    # but a long docstring stating reasons is a design note worth more than the
    # code, so only unexplained bulk is reported.
    bulky = (
        span > 0
        and doc_lines >= _MIN_ESSAY_LINES
        and doc_lines > _ESSAY_RATIO * span
        and _WHY_MARKER.search(doc) is None
    )
    if not bulky:
        return None
    return (
        "oversized-docstring",
        f"{name}: {doc_lines} docstring lines over a {span}-line body, no reason given",
    )


def audit_docstrings(path: Path, source: str) -> list[Finding]:
    try:
        tree = ast.parse(source)
    except SyntaxError:
        return []

    findings: list[Finding] = []
    for name, node in _docstring_targets(tree):
        doc = ast.get_docstring(node, clean=True)
        if doc is None or doc == "":
            continue
        expr = node.body[0] if len(node.body) > 0 else None
        line = expr.lineno if isinstance(expr, ast.Expr) else getattr(node, "lineno", 1)
        end = line
        if isinstance(expr, ast.Expr) and expr.end_lineno is not None:
            end = expr.end_lineno
        if (hit := _docstring_rule(name, doc, _body_span(node))) is not None:
            findings.append(Finding(path, line, hit[0], hit[1], end))
    return findings


def _target(argument: str) -> tuple[Path, set[int] | None]:
    """Split FILE:LINE,LINE from a bare FILE.

    Rsplit on the last colon so a colon inside a directory name stays part of
    the path.
    """
    if ":" in argument:
        head, _, tail = argument.rpartition(":")
        if head != "" and re.fullmatch(r"\d+(?:,\d+)*", tail) is not None:
            return Path(head), {int(n) for n in tail.split(",")}
    return Path(argument), None


def audit(path: Path, lines: set[int] | None = None) -> list[Finding]:
    try:
        source = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return []

    findings = audit_comments(path, source) + audit_docstrings(path, source)
    if lines is not None:
        # A docstring spans lines, so it counts as touched when any line of it
        # was added: a session that rewrites the middle of one owns the whole.
        findings = [f for f in findings if not lines.isdisjoint(f.span)]
    if len(findings) == 0:
        return []

    # A handful of findings in a large file is a house style, not a narrated
    # file. Reporting those trains the agent to ignore the hook.
    code_lines = sum(1 for line in source.splitlines() if line.strip() != "")
    if len(findings) < _ALWAYS_REPORT_AT and len(findings) < code_lines * _MIN_DENSITY:
        return []
    return findings


def _sort_key(finding: Finding) -> tuple[str, int]:
    return str(finding.path), finding.line


def main(argv: list[str]) -> int:
    targets = [_target(arg) for arg in argv] if len(argv) > 0 else [(Path(), None)]
    files: list[tuple[Path, set[int] | None]] = []
    for path, lines in targets:
        if path.is_dir():
            files.extend(
                (p, None)
                for p in sorted(path.rglob("*"))
                if p.suffix in CODE_SUFFIXES and p.is_file()
            )
        elif path.suffix in CODE_SUFFIXES and path.is_file():
            files.append((path, lines))

    findings: list[Finding] = [f for file, lines in files for f in audit(file, lines)]
    if len(findings) == 0:
        return 0

    findings.sort(key=_sort_key)
    report = "\n".join(str(f) for f in findings)
    _ = sys.stdout.write(f"{report}\n")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
