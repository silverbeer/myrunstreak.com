# Claude Code Guidelines for MyRunStreak.com

This document defines the development standards and best practices for AI assistants (Claude) working on this project.

## 🎯 Core Principles

**Modern Python Development:**
- ✅ **ALWAYS use UV** - Never use pip, pipenv, poetry, or virtualenv directly
- ✅ **Type hints everywhere** - Strict mypy configuration
- ✅ **Pydantic v2** for all data models and settings
- ✅ **Ruff** for linting and formatting (replaces black, isort, flake8)
- ✅ **pytest** for all testing with coverage requirements

## 📦 Package Management

### UV is the ONLY package manager

**✅ CORRECT:**
```bash
uv sync                    # Install dependencies
uv sync --all-extras       # Install with dev dependencies
uv add httpx              # Add new dependency
uv add --dev pytest       # Add dev dependency
uv run pytest             # Run tests
uv run ruff check .       # Run linter
uv run mypy src/          # Run type checker
```

**❌ WRONG:**
```bash
pip install -r requirements.txt   # NO! Use UV
pip install pytest                # NO! Use UV
python -m pytest                  # NO! Use 'uv run pytest'
source .venv/bin/activate         # Not needed with 'uv run'
virtualenv venv                   # NO! UV manages virtualenvs
```

### Virtual Environment

UV automatically manages the `.venv` directory:
- Created automatically on `uv sync`
- No need to manually activate
- Use `uv run <command>` to run in the venv
- If you must activate: `source .venv/bin/activate`

### Dependencies

**All dependencies go in `pyproject.toml`:**

```toml
[project]
dependencies = [
    "httpx>=0.27.0",      # Production deps
]

[project.optional-dependencies]
dev = [
    "pytest>=8.3.0",       # Dev/test deps
    "ruff>=0.7.0",
]
```

**Never create:**
- ❌ requirements.txt
- ❌ requirements-dev.txt
- ❌ Pipfile
- ❌ poetry.lock
- ❌ setup.py (use pyproject.toml)

## 🔧 Code Quality Tools

### Ruff (Linting & Formatting)

**Ruff replaces:** black, isort, flake8, pyupgrade

```bash
# Format code
uv run ruff format .

# Check linting
uv run ruff check .

# Fix auto-fixable issues
uv run ruff check --fix .
```

**Configuration in `pyproject.toml`:**
```toml
[tool.ruff]
line-length = 100
target-version = "py312"
```

### Mypy (Type Checking)

**Strict mode enabled:**

```bash
uv run mypy src/
```

**All code must have type hints:**

```python
# ✅ CORRECT
def process_run(activity_id: str, distance: float) -> dict[str, Any]:
    return {"id": activity_id, "distance": distance}

# ❌ WRONG - Missing type hints
def process_run(activity_id, distance):
    return {"id": activity_id, "distance": distance}
```

### Pytest (Testing)

```bash
# Run all tests
uv run pytest

# Run with coverage
uv run pytest --cov=src --cov-report=term-missing

# Run specific test file
uv run pytest tests/test_models.py

# Run with verbose output
uv run pytest -v
```

**Test file naming:**
- `test_*.py` for test files
- `test_*` for test functions
- Use fixtures for setup/teardown

## 📝 Code Style

### Import Organization

Ruff handles import sorting automatically:

```python
# Standard library
import json
import logging
from datetime import date, datetime
from typing import Any

# Third-party
import httpx
from pydantic import BaseModel, Field

# Local
from src.shared.models import Activity
from src.shared.smashrun import SmashRunAPIClient
```

### Type Hints

**Always use modern Python 3.12+ type hints:**

```python
# ✅ CORRECT (Python 3.12+)
def get_runs(count: int) -> list[dict[str, Any]]:
    pass

def process_optional(value: str | None) -> dict[str, int | float]:
    pass

# ❌ WRONG (old style)
from typing import List, Dict, Optional, Union

def get_runs(count: int) -> List[Dict[str, Any]]:  # Use list, not List
    pass

def process_optional(value: Optional[str]) -> Dict[str, Union[int, float]]:
    pass
```

### Pydantic Models

**Always use Pydantic v2 syntax:**

```python
from pydantic import BaseModel, Field

class Activity(BaseModel):
    activity_id: str = Field(description="Unique identifier")
    distance: float = Field(gt=0, description="Distance in kilometers")

    model_config = {"populate_by_name": True}  # v2 syntax
```

### String Formatting

**Use f-strings:**

```python
# ✅ CORRECT
logger.info(f"Synced {count} runs since {date}")

# ❌ WRONG
logger.info("Synced {} runs since {}".format(count, date))
logger.info("Synced %s runs since %s" % (count, date))
```

## 🏗️ Project Structure

### Module Organization

```
src/
  shared/          # Shared code used by multiple lambdas
    models/        # Pydantic models
    duckdb_ops/    # Database operations
    smashrun/      # SmashRun integration
  lambdas/         # Lambda function handlers
    sync_runs/
    api/
  utils/           # General utilities
```

### Import Paths

**Use absolute imports from `src/`:**

```python
# ✅ CORRECT
from src.shared.models import Activity
from src.shared.smashrun import SmashRunAPIClient

# ❌ WRONG
from ..models import Activity           # Relative imports
from shared.models import Activity      # Missing src prefix
```

## 🧪 Testing Requirements

### Coverage Requirements

- Minimum 80% code coverage
- All new features must have tests
- Critical paths require 100% coverage

### Test Structure

```python
import pytest
from src.shared.models import Activity

def test_activity_validation():
    """Test that Activity model validates correctly."""
    activity = Activity(
        activityId="test-123",
        startDateTimeLocal=datetime.now(),
        distance=5.0,
        duration=1800,
    )
    assert activity.distance == 5.0

def test_activity_invalid_distance():
    """Test that invalid distance raises error."""
    with pytest.raises(ValueError):
        Activity(
            activityId="test-123",
            startDateTimeLocal=datetime.now(),
            distance=0,  # Invalid
            duration=1800,
        )
```

## 🚫 What NOT to Do

### Never Use These

❌ **pip** - Use `uv` instead
❌ **virtualenv** - UV manages venvs
❌ **requirements.txt** - Use pyproject.toml
❌ **setup.py** - Use pyproject.toml
❌ **black** - Use ruff format
❌ **isort** - Use ruff check
❌ **flake8** - Use ruff check
❌ **typing.List/Dict** - Use list/dict (3.12+)
❌ **typing.Optional** - Use `X | None`

### Anti-Patterns

```python
# ❌ WRONG - No type hints
def process_data(data):
    return data["value"]

# ❌ WRONG - Bare except
try:
    process()
except:
    pass

# ❌ WRONG - Mutable default argument
def add_item(items=[]):
    items.append("new")
    return items

# ❌ WRONG - String concatenation in loops
result = ""
for item in items:
    result += str(item)
```

```python
# ✅ CORRECT - Type hints
def process_data(data: dict[str, Any]) -> str:
    return data["value"]

# ✅ CORRECT - Specific exception
try:
    process()
except ValueError as e:
    logger.error(f"Processing failed: {e}")

# ✅ CORRECT - None as default
def add_item(items: list[str] | None = None) -> list[str]:
    if items is None:
        items = []
    items.append("new")
    return items

# ✅ CORRECT - List comprehension or join
result = "".join(str(item) for item in items)
```

## 📚 Documentation

### Docstrings

**Use Google-style docstrings:**

```python
def sync_runs(access_token: str, since_date: date) -> int:
    """
    Sync runs from SmashRun to DuckDB.

    Args:
        access_token: Valid SmashRun access token
        since_date: Fetch runs on or after this date

    Returns:
        Number of runs synced

    Raises:
        HTTPError: If API request fails
    """
```

### Comments

- Explain **why**, not **what**
- Keep comments up to date
- Remove commented-out code (use git history)

## 🔄 Git Workflow

### Commits

**Use conventional commit messages:**

```
feat: Add SmashRun OAuth integration
fix: Handle expired tokens correctly
docs: Update Lambda deployment guide
test: Add tests for token refresh
refactor: Simplify database connection logic
```

### Branch Names

```
feature/lambda-daily-sync
fix/token-refresh-bug
docs/api-documentation
```

## 🎨 Claude Code Behavior

### When Writing Code

1. **Always check for existing patterns** - Follow project conventions
2. **Use UV for all Python operations** - Never suggest pip
3. **Add type hints** - Every function must be typed
4. **Write tests** - New code needs test coverage
5. **Use Pydantic** - For settings and data models
6. **Document decisions** - Explain non-obvious choices

### When Suggesting Commands

```bash
# ✅ CORRECT suggestions
uv run pytest
uv run ruff check .
uv add httpx

# ❌ WRONG suggestions
pip install pytest
python -m pytest
pip freeze > requirements.txt
```

### When Creating Files

- ✅ `pyproject.toml` for dependencies
- ✅ `.env.example` for environment templates
- ✅ `README.md` for project documentation
- ❌ Never create `requirements.txt`
- ❌ Never create `setup.py`

## 📖 Resources

- [UV Documentation](https://github.com/astral-sh/uv)
- [Ruff Documentation](https://docs.astral.sh/ruff/)
- [Pydantic v2 Documentation](https://docs.pydantic.dev/latest/)
- [Python 3.12+ Type Hints](https://docs.python.org/3/library/typing.html)

## ✅ Quick Reference

```bash
# Setup project
uv sync --all-extras

# Run tests
uv run pytest

# Code quality
uv run ruff format .
uv run ruff check .
uv run mypy src/

# Add dependency
uv add package-name
uv add --dev pytest-package

# Run scripts
uv run python scripts/test_local_sync.py

# Update dependencies
uv sync --upgrade
```

---

**Remember:** This project uses modern Python (3.12+) with UV. Always follow these guidelines to maintain consistency and code quality.
