---
description: Keep imports at top of file and avoid inline imports
paths:
  - "**/*.{py,pyi}"
---

# No inline imports

Always place imports at the top of the module. Do not put imports inside function bodies, type annotations, or interface fields unless a real circular dependency requires it. Document that reason next to the inline import.
