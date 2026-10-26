---
paths:
  - "**/*.py"
  - "**/pyproject.toml"
  - "**/requirements*.txt"
  - "**/conftest.py"
---

# Python (claude-kit)

- Run tools through the project's runner, as `.claude/kit/commands.env` does (`uv run`, `poetry run`, …).
  Never `pip install` into a global interpreter; adding a dependency is an ask-first change to the lockfile.
- Type hints on every public function and dataclass field. Prefer `dataclasses`/`pydantic` models over loose dicts
  at module boundaries. `Any` needs a one-line reason.
- Tests: pytest, one behaviour per test, named after it. Plain `assert`; fixtures for setup; `tmp_path` for files;
  `monkeypatch` only at the edges (clock, network, env). Fakes over mocks for your own ports.
- Errors: raise specific exceptions; never a bare `except:` or `except Exception: pass`. Re-raise with `from err`.
- Paths with `pathlib`, text with an explicit `encoding="utf-8"`. No `os.chdir` in library code.
- Logging with `logging`, not `print`, outside scripts and notebooks. Never log secrets or personal data.
- Money and other exact quantities: `decimal.Decimal` or integer minor units, never floats.
- Imports at the top, absolute within the package. No `from x import *`.
- Keep side effects under `if __name__ == "__main__":` so modules import cleanly in tests.
- Formatting and lint follow the project's ruff config; don't hand-format around it or add `# noqa` without a reason.
