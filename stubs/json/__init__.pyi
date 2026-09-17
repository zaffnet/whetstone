from collections.abc import Callable
from typing import Protocol

class _SupportsWrite(Protocol):
    def write(self, s: str, /) -> object: ...

class JSONDecodeError(ValueError):
    msg: str
    doc: str
    pos: int
    lineno: int
    colno: int

def loads(s: str | bytes | bytearray) -> object: ...
def dumps(
    obj: object,
    *,
    ensure_ascii: bool = True,
    indent: int | str | None = None,
    default: Callable[[object], object] | None = None,
    sort_keys: bool = False,
) -> str: ...
def dump(
    obj: object,
    fp: _SupportsWrite,
    *,
    ensure_ascii: bool = True,
    indent: int | str | None = None,
    default: Callable[[object], object] | None = None,
    sort_keys: bool = False,
) -> None: ...
