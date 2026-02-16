# Agent Integration

Context Grabber provides agent skill definitions that teach AI coding agents (Claude Code, OpenCode, Cursor, and others) how to use `cgrab` for context capture workflows.

## Installation Methods

### skills.sh (recommended)

The easiest way to install the Context Grabber skill for your AI agent:

```bash
npx skills add anthonylu23/context_grabber
```

This uses the [skills.sh](https://skills.sh) ecosystem to discover and install the skill directly from the GitHub repository.

### cgrab CLI

If you have `cgrab` installed:

```bash
# Interactive installer (requires Bun)
cgrab skills install

# Embedded fallback (no Bun needed, Claude Code + OpenCode only)
cgrab skills install --agent claude --scope project
```

When Bun is available, `cgrab skills install` launches a full interactive experience supporting Claude Code, OpenCode, and Cursor. Without Bun, it falls back to a non-interactive embedded installer for Claude Code and OpenCode (Cursor requires Bun for `.mdc` format conversion).

### npx interactive installer

```bash
npx @context-grabber/agent-skills
```

Interactive prompt-based installer with agent and scope selection.

### Manual installation

Copy the skill files from `packages/agent-skills/skill/` to the agent-specific directory:

| Agent      | Global path                                          | Project path                          |
| ---------- | ---------------------------------------------------- | ------------------------------------- |
| Claude Code | `~/.claude/skills/context-grabber/`                    | `.claude/skills/context-grabber/`       |
| OpenCode   | `~/.config/opencode/skills/context-grabber/`           | `.opencode/skills/context-grabber/`     |
| Cursor     | `~/.cursor/rules/context-grabber.mdc` (adapted format) | `.cursor/rules/context-grabber.mdc`     |

## What the Skill Teaches Agents

Once installed, the skill instructs the agent on:

1. **When to use `cgrab`** — browser tab capture, desktop app context, inventory of open tabs/apps
2. **Prerequisites** — `cgrab` on PATH, optional ContextGrabber.app and Bun for browser capture
3. **Core workflow** — inventory (`cgrab list`) → select target → capture (`cgrab capture`) → use output
4. **Command reference** — all flags, selectors, output formats, environment variables
5. **Output format** — YAML frontmatter, summary, key points, content chunks, raw excerpt, links/metadata
6. **Error handling** — common failures and recovery steps via `cgrab doctor`

## Skill File Structure

```
packages/agent-skills/skill/
  SKILL.md                         # Core skill definition (YAML frontmatter + instructions)
  references/
    cli-reference.md               # Complete CLI command/flag/env var reference
    output-schema.md               # Markdown + JSON output structure documentation
    workflows.md                   # Agent workflow patterns and examples
```

The skill files are maintained in three synchronized locations:

| Location                      | Purpose                                |
| ----------------------------- | -------------------------------------- |
| `packages/agent-skills/skill/`  | Canonical source (npm installer)       |
| `cgrab/internal/skills/`        | Go `embed` copy (CLI fallback)           |
| `skills/context-grabber/`       | skills.sh ecosystem discovery          |

CI verifies all three stay in sync via `scripts/check-skill-sync.sh`.

## Uninstallation

```bash
# Via skills.sh
npx skills remove anthonylu23/context_grabber

# Via cgrab CLI
cgrab skills uninstall

# Via npx interactive installer
npx @context-grabber/agent-skills --uninstall
```

## Developing Skills

When editing skill content, always edit the canonical source at `packages/agent-skills/skill/` and then copy changes to:
- `cgrab/internal/skills/` (for the Go embed fallback)
- `skills/context-grabber/` (for skills.sh discovery)

Run `scripts/check-skill-sync.sh` locally to verify all copies match before committing.
