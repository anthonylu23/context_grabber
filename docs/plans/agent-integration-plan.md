# Agent Integration Plan

**Status: All phases complete.**

## Goal

Make `cgrab` discoverable and usable by AI coding agents (Claude Code, Cursor, and others) through a standard skill definition and interactive installer. Distribution should work via both `npx` (npm ecosystem) and `cgrab skills install` (CLI-native).

## Architecture

### Skill Format

Follow the Vercel/skills.sh ecosystem conventions:

```
SKILL.md              # YAML frontmatter (name, description, triggers) + instructions
references/           # Supplementary reference docs
  cli-reference.md
  output-schema.md
  workflows.md
```

Frontmatter schema:
```yaml
---
name: context-grabber
description: >
  Capture browser tabs and desktop app context as structured markdown
  for LLM workflows. Use when developers need to: (1) gather context
  from open browser tabs or running desktop apps, (2) create structured
  markdown from web pages or application state, (3) inventory open tabs
  or running apps. Triggers on: "cgrab", "context grabber", "capture
  context", "browser tabs", "desktop capture", "grab context".
---
```

### Install Targets

| Agent      | Global install path                                                      | Project install path               |
| ---------- | ------------------------------------------------------------------------ | ---------------------------------- |
| Claude Code | `~/.agents/skills/context-grabber/` + symlink `~/.claude/skills/context-grabber` | `.claude/skills/context-grabber/`  |
| OpenCode   | `~/.agents/skills/context-grabber/` + symlink `~/.config/opencode/skills/context-grabber` | `.opencode/skills/context-grabber/`  |
| Cursor     | `~/.cursor/rules/context-grabber.mdc` (adapted format)                   | `.cursor/rules/context-grabber.mdc` |

Global installs use `~/.agents/skills/` as the canonical location with symlinks into each agent's skill directory. This mirrors how existing Vercel skills are installed.

### Install Channels

```
npx skills add anthonylu23/context_grabber  # skills.sh ecosystem (GitHub-based)
npx @context-grabber/agent-skills           # npm interactive installer (if published)
cgrab skills install                        # CLI-native (prefers bunx delegation, go:embed fallback)
```

## Package Layout

```
packages/agent-skills/
  package.json              # @context-grabber/agent-skills, bin entry
  skill/
    SKILL.md                # Canonical skill definition
    references/
      cli-reference.md      # Full command, flag, and env var reference
      output-schema.md      # Markdown output structure + JSON mode docs
      workflows.md          # Common agent workflow patterns
  src/
    install.ts              # Interactive installer (bin entrypoint)
    targets/
      claude.ts             # Claude Code install/uninstall logic
      opencode.ts           # OpenCode install/uninstall logic
      cursor.ts             # Cursor install/uninstall logic (SKILL.md -> .mdc adapter)
    utils.ts                # Shared fs/path helpers
```

### Go CLI Embedding

```
cgrab/internal/skills/
  SKILL.md                  # Synced copy of packages/agent-skills/skill/SKILL.md
  references/               # Synced copies of reference docs
```

CI check: verify `cgrab/internal/skills/` matches `packages/agent-skills/skill/` to prevent drift.

## Skill Content (SKILL.md)

The skill instructs agents on:

1. **When to use** — user asks about browser tabs, desktop context, capturing pages, or agent context workflows
2. **Prerequisites** — `cgrab` binary on PATH, `ContextGrabber.app` for desktop capture (optional for browser-only)
3. **Core workflow pattern** — inventory → select → capture → use output
4. **Commands with examples**:
   - `cgrab list` / `cgrab list --tabs` / `cgrab list --apps`
   - `cgrab capture --focused`
   - `cgrab capture --tab 1:2 --browser safari`
   - `cgrab capture --app Finder`
   - `cgrab doctor` (diagnostics)
5. **Output format** — deterministic markdown with YAML frontmatter, or JSON via `--format json`
6. **Error handling** — common failures (permissions, extension not installed, app not running) and recovery steps
7. **Environment variables** — overrides for non-standard setups

Reference docs provide the detailed contracts agents need for programmatic use (JSON schemas, full flag lists, output structure).

## Interactive Installer UX

### npx path

```bash
$ npx @context-grabber/agent-skills

Context Grabber — Agent Skill Installer

? Which agents do you want to install for?
  [x] Claude Code
  [ ] OpenCode
  [ ] Cursor

? Install scope?
  ( ) Global — available in all projects
  (o) Project — this project only

Installing for Claude Code (project scope)...
  Created .claude/skills/context-grabber/SKILL.md
  Created .claude/skills/context-grabber/references/cli-reference.md
  Created .claude/skills/context-grabber/references/output-schema.md
  Created .claude/skills/context-grabber/references/workflows.md

Done. The agent can now discover and use cgrab.
```

### cgrab CLI path

```bash
$ cgrab skills install

Context Grabber — Agent Skill Installer

? Which agents do you want to install for?
  [x] Claude Code
  [ ] OpenCode
  [ ] Cursor

? Install scope?
  ( ) Global — available in all projects
  (o) Project — this project only

Installing for Claude Code (project scope)...
  ...
```

Under the hood: `cgrab skills install` tries `bunx @context-grabber/agent-skills` first. If bun is unavailable, falls back to copying `go:embed`-ed skill files directly.

### Uninstall

```bash
npx @context-grabber/agent-skills --uninstall
cgrab skills uninstall
```

Same interactive prompts: which agents, which scope. Removes the installed skill files/symlinks.

## Implementation Phases

### Phase 1: Skill Content ✓

Write the SKILL.md and reference documents. This is the core deliverable — everything else is distribution.

Tasks:
1. Create `packages/agent-skills/skill/SKILL.md` with frontmatter and agent instructions
2. Create `packages/agent-skills/skill/references/cli-reference.md` — full command reference
3. Create `packages/agent-skills/skill/references/output-schema.md` — markdown structure docs
4. Create `packages/agent-skills/skill/references/workflows.md` — agent workflow patterns
5. Review skill content against actual CLI behavior (`cgrab --help`, `cgrab list --help`, etc.)

### Phase 2: npx Installer ✓

Build the interactive installer as an npm package.

Tasks:
1. Create `packages/agent-skills/package.json` with bin entry
2. Implement installer prompts (agent selection, scope selection)
3. Implement install logic per agent target (file copy, symlink creation, .mdc adaptation)
4. Implement uninstall logic
5. Add `--uninstall` flag support
6. Test: `bun run packages/agent-skills/src/install.ts` locally
7. Validate install paths for each agent target

### Phase 3: cgrab CLI Subcommand ✓

Add `cgrab skills install` and `cgrab skills uninstall`.

Tasks:
1. Create `cgrab/cmd/skills.go` with `install` and `uninstall` subcommands
2. Create `cgrab/internal/skills/` with embedded copies of skill files
3. Implement bun delegation: try `bunx @context-grabber/agent-skills` first
4. Implement embedded fallback: copy go:embed files to target paths
5. Add CI sync check script to verify embedded files match canonical source
6. Tests for install path resolution and embed fallback logic

### Phase 4: skills.sh Publishing ✓

Make the skill discoverable in the skills.sh ecosystem.

The skills.sh ecosystem is GitHub-repo-based, not npm-based. The CLI (`npx skills add <owner/repo>`) fetches directly from GitHub. Skills must be in a `skills/<name>/SKILL.md` directory at the repo root, following the convention established by `vercel-labs/agent-skills` and `anthropics/skills`.

Tasks:
1. ~~Verify skill format is compatible with `npx skills add`~~ ✓ — SKILL.md format (YAML frontmatter + markdown) matches the convention
2. ~~Create `skills/context-grabber/` directory at repo root with SKILL.md + references/~~ ✓
3. ~~Update sync check script to verify all 3 skill file locations match~~ ✓
4. Test: `npx skills add anthonylu23/context_grabber` installs correctly (requires public repo)
5. Leaderboard ranking will auto-populate as users install via `npx skills add`

Note: the original plan assumed npm publishing was needed. In practice, skills.sh pulls from GitHub directly. The npm package (`@context-grabber/agent-skills`) remains useful for the interactive installer (`npx @context-grabber/agent-skills`) but is not required for skills.sh discovery.

### Phase 5: Documentation ✓

Tasks:
1. Create `docs/codebase/usage/agent-workflows.md` — human-readable guide
2. Update README.md with agent skill installation section
3. Update project plan next steps
4. Update CLI component docs (`docs/codebase/components/companion-cli.md`)

## Dependencies

- `@inquirer/prompts` (or similar) for interactive terminal prompts in the TS installer
- No new Go dependencies — `go:embed`, `os`, `os/exec` from stdlib are sufficient

## Exit Criteria

- `npx skills add anthonylu23/context_grabber` installs skill files for the detected agent
- `npx @context-grabber/agent-skills` (if published to npm) installs a working skill for Claude Code, OpenCode, Cursor
- `cgrab skills install` works with bun present and without (embedded fallback)
- Installed skill is picked up by the target agent and triggers on relevant queries
- Skill content accurately reflects current CLI capabilities and output format
- All 3 skill file locations (canonical, go:embed, skills.sh) stay in sync via CI check
