# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Rikugan is a reverse-engineering agent plugin for **IDA Pro** and **Binary Ninja** that integrates a multi-provider LLM directly into the disassembler UI. It has its own generator-based agent loop, in-process tool orchestration, streaming UI, multi-tab chat, session persistence, MCP client support, and host-native tool sets.

Entry points:
- `rikugan_plugin.py` — IDA Pro plugin (`PLUGIN_ENTRY()`)
- `rikugan_binaryninja.py` — Binary Ninja plugin (registers at import)

## Development Commands

```bash
./ci-local.sh          # Run CI checks (ruff, mypy, pytest, desloppify)
./ci-local.sh --fix    # Auto-fix ruff formatting issues

python3 -m pytest tests/ -v                    # Run all tests
python3 -m pytest tests/providers/ -v           # Run provider tests only
python3 -m ruff check rikugan/ --fix           # Lint + auto-fix
python3 -m mypy rikugan/core rikugan/providers  # Type check
```

Branch model: `feat/*` / `fix/*` → `dev` → `main`. Direct pushes to `main` are blocked.

## Architecture

### Dual-Host Structure

The codebase is organized around two host packages that implement the same interfaces:

```
rikugan/ida/     — IDA Pro tools + UI
rikugan/binja/   — Binary Ninja tools + UI
rikugan/         — Shared: agent/, core/, providers/, tools/, ui/, state/, mcp/, skills/
```

Tools are implemented once in `rikugan/tools/` (shared) or `rikugan/<host>/tools/` (host-specific). Host-specific tools import from `rikugan.tools.base` (the `@tool` decorator) and are registered in the host's `registry.py`.

### Generator-Based Agent Loop

The core loop in `rikugan/agent/loop.py` is a Python generator (`AgentLoop.run()`) that yields `TurnEvent` objects. The UI consumes events from a queue via `QTimer` polling (50ms interval).

```
User message → command detection → skill resolution → build system prompt
    → stream LLM response → intercept tool calls → execute tools → feed results back → repeat
```

### TurnEvent System

`rikugan/agent/turn.py` defines `TurnEvent` / `TurnEventType`. Events flow: `AgentLoop.run()` → `queue.Queue` → `BackgroundAgentRunner` → `QTimer._poll_events()` → `ChatView.handle_event()`. **No Qt signals cross threads.**

### Tool Framework

Tools use the `@tool` decorator from `rikugan/tools/base.py`:
- Generates JSON schema from function signature
- Wraps with `@idasync` for thread-safe IDA API access
- Registers as `func._tool_definition`

Add new tools: create function with `@tool(category="...")`, register in `rikugan/<host>/tools/registry.py`.

### Session / Multi-Tab Model

Each tab is an independent `SessionState` managed by `SessionControllerBase`. Sessions auto-save per file (IDB/BNDB path) and are restored on reopen.

### Threading Model

- **Agent runs in `threading.Thread`** (BackgroundAgentRunner)
- **IDA API calls must be on main thread** — `@idasync` decorator handles this
- **Binary Ninja API is thread-safe** — no marshalling needed
- **UI polling**: `QTimer` polls `queue.Queue` every 50ms
- **Cancellation**: `threading.Event` checked at every yield point, sleep iteration, and tool dispatch boundary

### System Prompt Architecture

Prompts are assembled in `rikugan/agent/system_prompt.py`:
```
base prompt (ida.py or binja.py)
  + binary context
  + cursor position
  + tool list
  + active skill bodies
  + persistent memory (RIKUGAN.md)
```

Host-specific base prompts are in `rikugan/agent/prompts/`.

## Critical Security Notes

Rikugan processes **adversarial binaries**. Binary content (strings, names, decompiled code) flows directly into LLM prompts. Every data path from binary to model is an attack surface.

### Mandatory Sanitization

All untrusted data **must** pass through `rikugan/core/sanitize.py`:
- `sanitize_tool_result()` — every tool result
- `sanitize_mcp_result()` — every MCP server response
- `sanitize_binary_context()` — binary info in system prompt
- `sanitize_memory()` — RIKUGAN.md content
- `strip_injection_markers()` — removes LLM role/injection patterns at point of entry

Data enters prompts wrapped in delimiters (`<tool_result>`, `<binary_info>`, etc.) with a `DATA_INTEGRITY_SECTION` in the system prompt instructing the model to treat delimited content as data, not instructions.

### Script Execution Safety

The `execute_python` tool (`rikugan/tools/scripting.py`) is the highest-risk surface:
- `rikugan/tools/script_guard.py` AST-checks code before user approval
- Blocked: `subprocess`, `os.system`, `os.popen`, `os.exec*`, `os.spawn*`, `__import__`
- Runs in sandboxed `exec()` with redirected stdout/stderr
- **Never auto-approve** script execution

### IDA API Imports

**All `ida_*` imports must use `importlib.import_module()` inside `try/except ImportError`**. This avoids Shiboken UAF crashes when the module is loaded outside IDA. See `rikugan/core/thread_safety.py` for the `@idasync` decorator.

**Python 3.10 is the safest choice for IDA Pro.** Shiboken has a known UAF bug on Python > 3.10 during Qt signal dispatch.

### Mutating Tools and Undo

Tools with `mutating=True` in `@tool` have pre-state captured for undo. Mutation records are stored in `rikugan/agent/mutation.py`. Every mutating tool must have corresponding `build_reverse_record()` and `capture_pre_state()` entries.

## Important Code Conventions

- **Type hints everywhere** — function signatures, dataclass fields, return types
- **Dataclasses over dicts** — structured data (config, state, events, records)
- **`from __future__ import annotations`** at top of every module
- **f-strings for formatting** — hex: `f"0x{ea:x}"`
- **No bare `except:`** — always catch specific exceptions
- **No mutable default arguments** — use `field(default_factory=...)` or `None` + `if`
- **Never use Qt signals across threads** — use `queue.Queue` + `QTimer` polling

## Key Files

| File | Role |
|------|------|
| `rikugan/agent/loop.py` | Core agent loop — generator-based turn cycle |
| `rikugan/agent/turn.py` | TurnEvent / TurnEventType definitions |
| `rikugan/tools/base.py` | `@tool` decorator, `ToolDefinition` |
| `rikugan/tools/registry.py` | `ToolRegistry` — registration, dispatch |
| `rikugan/core/host.py` | Host context singleton (BinaryView, address, navigate callback) |
| `rikugan/core/thread_safety.py` | `@idasync` decorator for IDA main-thread marshalling |
| `rikugan/core/sanitize.py` | All sanitization functions |
| `rikugan/providers/base.py` | `LLMProvider` ABC |
| `rikugan/ui/panel_core.py` | `PanelCore` — multi-tab chat, event routing |
| `rikugan/state/session.py` | `SessionState` — message history, token tracking |

## Adding New Features

**New tool**: `@tool` decorator + register in host's `registry.py`. Mutating tools need undo support in `mutation.py`.

**New skill**: Markdown file with YAML frontmatter in `rikugan/skills/builtins/<slug>/SKILL.md`.

**New host**: Create `rikugan/<host>/` with `tools/` + `ui/` sub-packages. See AGENTS.md §"How to Add a New Host".

**New config field**: Add to `RikuganConfig` dataclass, wire in `load()` / `validate()` / `save()` in `config.py`, and in `settings_dialog.py`.

For full technical documentation, see [AGENTS.md](AGENTS.md) (deep internals) and [DEVELOPMENT.md](DEVELOPMENT.md) (dev setup, branch workflow, release process).
