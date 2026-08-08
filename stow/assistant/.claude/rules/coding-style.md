# Coding Style

- **Immutability (critical)**: never mutate objects/arrays in place; return new copies. Prevents hidden side effects, eases debugging, enables safe concurrency.
- **Files**: many small files over few large ones; 200-400 lines typical, 800 max; organize by feature/domain, not by type.
- **Functions**: small (<50 lines); nesting <=4 levels.
- **Error handling**: handle explicitly at every level; user-friendly messages in UI-facing code, detailed context in server logs; never silently swallow errors.
- **Input validation**: validate all external data at system boundaries (schema-based where available); fail fast with clear messages; never trust user input, API responses, or file content.
- **No emojis** in code, comments, or documentation.
- **No hardcoded values**: use constants or config.
