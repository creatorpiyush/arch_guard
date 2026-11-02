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

The [arch-guard skill](https://github.com/creatorpiyush/arch_guard/blob/main/skills/arch-guard/SKILL.md) tells an agent how to set up arch_guard, read its reports, and fix violations and cycles in the code without weakening your rules. It uses the [Agent Skills](https://agentskills.io) format.

Claude Code, for one project (commit it so your team gets it too):

```bash
mkdir -p .claude/skills/arch-guard
curl -fsSL -o .claude/skills/arch-guard/SKILL.md \
  https://raw.githubusercontent.com/creatorpiyush/arch_guard/main/skills/arch-guard/SKILL.md
```

For all your projects, use `~/.claude/skills/arch-guard` instead. Other agents that support Agent Skills: put `SKILL.md` in their skills folder, under `arch-guard/`.

## Without skills: AGENTS.md

For agents that read `AGENTS.md`, `CLAUDE.md`, `.cursor/rules` or `.github/copilot-instructions.md`, add this:

```markdown
## Architecture

This project's architecture rules are enforced by arch_guard (config: `arch_guard.yaml`).

- After changing imports, run `dart run arch_guard`. Exit code 0 means clean.
- Fix a layer violation by inverting the dependency (interface in the importing layer)
  or moving the code. For a cycle, start with the import on the `Suggested fix:` line.
- Do not edit `allowed_imports`, `forbidden_packages` or the metric limits, and do not
  run `--update-baseline`, without asking first.
- `dart run arch_guard --explain <file>` shows why a file is in a cycle.
```
