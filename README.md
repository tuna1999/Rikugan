# Iris — The IDA Pro companion

An IDA Pro plugin that integrates a multi-provider LLM agent as a first-class reverse engineering companion. Iris provides an agentic loop with streaming, 57 purpose-built IDA tools, 7 built-in analysis skills, MCP client, and a native Qt chat panel, all accessible through a single hotkey.


## Is this another MCP client?

No, Iris is an agent built to live inside IDA Pro. It does not consume an MCP server to interact with IDA — it has its own agentic loop, context management, and tool orchestration layer running entirely in-process. The agent loop is a generator-based turn cycle: each user message kicks off a stream→execute→repeat pipeline where the LLM response is streamed token-by-token, tool calls are intercepted and dispatched to 57 IDA-native handlers (marshalled to the main thread via `execute_sync`), and the results are fed back as the next turn's context. The loop runs in a background thread while a Qt timer polls events into the UI, so IDA never blocks. It supports automatic error recovery, mid-run user questions (`ask_user`), plan mode for multi-step workflows, and message queuing — all without leaving IDA.

It has a set of tools exposed to the agent that encapsulate many IDA interactions. The agent was really born ***living*** and ***breathing*** reversing.

Advantages:

- No need to switch to an external MCP client such as Claude Code
- Assistant first, not made to do your job (unless you ask it)
- Expandable to many LLM providers and local installations (Ollama)
- Quick enabling, just hit Ctrl+Shift+I and the chat will appear

![Iris chat panel](assets/chat.png)

Also, building agents is an amazing area of study, especially coding with them.


## Features

- **57 IDA tools** — navigation, decompiler, disassembly, xrefs, strings, annotations, type engineering, microcode, scripting
- **7 built-in skills** — malware analysis, deobfuscation, vulnerability audit, driver analysis, CTF solving, and more
- **MCP client** — connect external MCP servers, their tools appear alongside built-in ones
- **9 context menu actions** — right-click in disasm/pseudocode for instant analysis
- **5 LLM providers** — Anthropic (Claude), OpenAI, Gemini, Ollama, OpenAI-compatible
- **Message queuing** — send follow-up messages while the agent is working; they auto-submit when the current turn finishes
- **Microcode tools** — read, NOP, and install custom optimizers at any Hex-Rays maturity level
- **Session persistence** — auto-save/restore conversations across IDA restarts

## Requirements

- IDA Pro 9.0+ with Hex-Rays decompiler (recommended)
- Python 3.9+ (3.14 is known to have problems with Qt)
- At least one LLM provider


## Installation

Clone this repository, then on Linux or macOS run:

```bash
./install.sh
```

This will automatically place the plugin in the `~/.idapro/plugins` folder and create its files at `~/.iris/`.

### Set your API key

Iris has a settings dialog to configure your model of choice; it comes with predefined values. Open Iris → click Settings → paste your key. Keys are persisted to `~/.idapro/iris/config.json`.

![Settings dialog](assets/settings.png)

**Anthropic OAuth:** If you have Claude Code installed and authenticated, Iris auto-detects the OAuth token from the macOS Keychain. Otherwise, you can get the OAuth token by running `claude setup-token` (you'll have to log in again).



## Usage

### Open the panel

Press **Ctrl+Shift+I** or go to **Edit → Plugins → Iris**.

![Panel overview](assets/panel.png)


Type a message and press **Enter** to send. Iris streams the response and executes IDA tools as needed.

- **Enter** — send message
- **Shift+Enter** — newline
- **Escape** — cancel the current run (also clears queued messages)

### Message queuing

You can send messages while the agent is working. They appear as `[queued]` in the chat and auto-submit when the current turn finishes. Hit **Stop** to cancel the running turn and discard all queued messages.

### Context menu

Right-click in the disassembly or pseudocode view:

| Action | Views | Behavior |
|--------|-------|----------|
| **Send to IRIS** | disasm, pseudo | Pre-fills input with selection (Ctrl+Shift+A) |
| **Explain this** | disasm, pseudo | Auto-explains the current function |
| **Rename with IRIS** | disasm, pseudo | Analyzes and renames with evidence |
| **Deobfuscate with IRIS** | disasm, pseudo | Systematic deobfuscation |
| **Find vulnerabilities** | disasm, pseudo | Security audit |
| **Suggest types** | disasm, pseudo | Infers types from usage patterns |
| **Annotate function** | pseudo | Adds comments to decompiled code |
| **Clean microcode** | pseudo | Identifies and NOPs junk microcode |
| **Xref analysis** | disasm, pseudo | Deep cross-reference tracing |

### Skills

Skills are reusable analysis workflows. Type `/` in the input area to see available skills with autocomplete.

**Built-in skills:**

| Skill | Description |
|-------|-------------|
| `/malware-analysis` | Windows PE malware — kill chain, IOC extraction, MITRE ATT&CK mapping |
| `/linux-malware` | ELF malware — packing detection, persistence, IOC extraction |
| `/deobfuscation` | String decryption, CFF removal, opaque predicates, MBA simplification, microcode cleaning |
| `/driver-analysis` | Windows kernel drivers — DriverEntry, dispatch table, IOCTL handlers |
| `/vuln-audit` | Buffer overflows, format strings, integer issues, memory safety |
| `/ctf` | Capture-the-flag — find the flag efficiently |
| `/generic-re` | General-purpose binary analysis |

**User skills:** Create custom skills in `~/.iris/skills/<slug>/SKILL.md`. User skills with the same slug override built-in ones.

Skill format:
```markdown
---
name: My Custom Skill
description: What it does in one line
tags: [analysis, custom]
---
Task: <instruction for the agent>

## Approach
...
```

### MCP Servers

Connect external MCP servers to extend Iris with additional tools. Configure in `~/.iris/mcp.json`:

```json
{
  "mcpServers": {
    "binary-ninja": {
      "command": "python",
      "args": ["-m", "binaryninja_mcp"],
      "env": {},
      "enabled": true
    }
  }
}
```

MCP tools appear alongside built-in tools with the prefix `mcp_<server>_<tool>`. The agent sees them in the tool list and can call them like any other tool.

## Tools

57 tools organized by category:

| Category | Tools |
|----------|-------|
| **Navigation** | `get_cursor_position`, `get_current_function`, `jump_to`, `get_name_at`, `get_address_of` |
| **Functions** | `list_functions`, `get_function_info`, `search_functions` |
| **Strings** | `list_strings`, `search_strings`, `get_string_at` |
| **Database** | `list_segments`, `list_imports`, `list_exports`, `get_binary_info`, `read_bytes` |
| **Disassembly** | `read_disassembly`, `read_function_disassembly`, `get_instruction_info` |
| **Decompiler** | `decompile_function`, `get_pseudocode`, `get_decompiler_variables` |
| **Xrefs** | `xrefs_to`, `xrefs_from`, `function_xrefs` |
| **Annotations** | `rename_function`, `rename_variable`, `set_comment`, `set_function_comment`, `rename_address`, `set_type` |
| **Types** | `create_struct`, `modify_struct`, `get_struct_info`, `list_structs`, `create_enum`, `modify_enum`, `get_enum_info`, `list_enums`, `create_typedef`, `apply_struct_to_address`, `apply_type_to_variable`, `set_function_prototype`, `import_c_header`, `suggest_struct_from_accesses`, `propagate_type`, `get_type_libraries`, `import_type_from_library` |
| **Microcode** | `get_microcode`, `get_microcode_block`, `nop_microcode`, `install_microcode_optimizer`, `remove_microcode_optimizer`, `list_microcode_optimizers`, `redecompile_function` |
| **Scripting** | `execute_python` (last resort — the agent prefers built-in tools) |

Decompiler and microcode tools require Hex-Rays. If unavailable, they return an error and all other tools continue to work.
