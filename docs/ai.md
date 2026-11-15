---
title: AI agents
---

# AI coding agents

Let Claude Code, Codex, Cursor, Copilot or another coding agent set up arch_guard for you, and teach it to keep your architecture rules from then on.

## Set up with one prompt

Paste this into your agent, in the root of your Dart or Flutter project:

```text
Set up arch_guard (https://pub.dev/packages/arch_guard) in this project, following
https://raw.githubusercontent.com/creatorpiyush/arch_guard/main/skills/arch-guard/SKILL.md.
Show me the preset `arch_guard init --dry-run` detects before writing the config, and
ask me before you create a baseline or loosen any rule.
```

The agent installs the package, picks a preset, writes `arch_guard.yaml`, runs the first check, and offers an architecture test, a CI workflow and IDE warnings.

## Install the skill

The [arch-guard skill](https://github.com/creatorpiyush/arch_guard/blob/main/skills/arch-guard/SKILL.md) tells an agent how to set up arch_guard, read its reports, trace an unwanted import with `why`, run only the tests a branch affects, and fix violations and cycles in the code without weakening your rules. It uses the [Agent Skills](https://agentskills.io) format.

Claude Code, for one project (commit it so your team gets it too):

```bash
mkdir -p .claude/skills/arch-guard
curl -fsSL -o .claude/skills/arch-guard/SKILL.md \
  https://raw.githubusercontent.com/creatorpiyush/arch_guard/main/skills/arch-guard/SKILL.md
```

For all your projects, use `~/.claude/skills/arch-guard` instead. Other agents that support Agent Skills: put `SKILL.md` in their skills folder, under `arch-guard/`.

## MCP server

`arch_guard mcp` is a [Model Context Protocol](https://modelcontextprotocol.io) server. With it, an agent asks before it writes an import ("may `lib/domain/user.dart` import `package:http`?") and gets the rule and a fix back, instead of finding out from a failed run.

Claude Code, in the project root:

```bash
claude mcp add arch_guard -- dart run arch_guard mcp
```

Cursor (`.cursor/mcp.json`), Claude Code (`.mcp.json`) and most other clients take the same JSON:

```json
{
  "mcpServers": {
    "arch_guard": { "command": "dart", "args": ["run", "arch_guard", "mcp"] }
  }
}
```

Codex (`~/.codex/config.toml`):

```toml
[mcp_servers.arch_guard]
command = "dart"
args = ["run", "arch_guard", "mcp"]
```

With the [standalone binary](getting-started.html) or `dart pub global activate arch_guard`, use `arch_guard mcp` as the command instead. The server checks the project in its working directory; pass a path (`arch_guard mcp packages/app`) for another one. It also takes `--scan-dir`, `--exclude` and `--[no-]workspace`.

| Tool | Arguments | Returns |
| :--- | :--- | :--- |
| `check` | `since` (optional git ref) | Every rule, like `arch_guard`: `passed`, the `failures`, `reportOnly` problems the config does not fail on, and config `warnings`. Baseline entries are left out. |
| `check_import` | `file`, `import` | Whether `file` may import the URI as written (`package:app/data/api.dart`, `../models/user.dart`, `dart:io`), and each layer, module, workspace or forbidden-package rule it would break, with a fix. The file need not exist. |
| `layer_of` | `file` | The file's layer and its `allowed_imports` and forbidden packages, its module and that module's public files, and its workspace package. |
| `why` | `from`, `to` | The shortest import chain, as [`arch_guard why`](cli.html#why-does-a-depend-on-b). |
| `affected` | `since` | Changed files and the tests, files and packages they can affect, as `arch_guard affected --json`. |
| `explain` | `file` | What the file imports, what imports it, and its cycle, as `arch_guard --explain`. |

Each call scans the project again, so answers follow the agent's edits.

## Without skills: AGENTS.md

For agents that read `AGENTS.md`, `CLAUDE.md`, `.cursor/rules` or `.github/copilot-instructions.md`, add this:

```markdown
## Architecture

This project's architecture rules are enforced by arch_guard (config: `arch_guard.yaml`).

- After changing imports, run `dart run arch_guard`. Exit code 0 means clean.
- Fix a layer violation by inverting the dependency (interface in the importing layer)
  or moving the code. For a cycle, start with the import on the `Suggested fix:` line.
- Do not edit `allowed_imports`, `forbidden_packages`, `modules` or the metric limits, and do not
  run `--update-baseline`, without asking first.
- `dart run arch_guard --explain <file>` shows why a file is in a cycle.
- `dart run arch_guard why <from> <to>` (e.g. `why lib/domain package:flutter`) prints the
  import chain that makes one file or folder depend on another, or on a package.
- `dart run arch_guard affected --since origin/main` lists the test files a branch can
  affect. If it prints nothing, no tests are affected: do not run `dart test` with no paths.
```
