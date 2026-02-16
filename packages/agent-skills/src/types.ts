/** Agent targets supported by the installer. */
export type AgentTarget = "claude" | "opencode" | "cursor";

/** Install scope — global or project-local. */
export type InstallScope = "global" | "project";

/** Result of an install or uninstall operation. */
export interface InstallResult {
  readonly agent: AgentTarget;
  readonly scope: InstallScope;
  readonly paths: readonly string[];
  readonly symlinks: readonly string[];
}

/** Canonical agent display names. */
export const AGENT_LABELS: Readonly<Record<AgentTarget, string>> = {
  claude: "Claude Code",
  opencode: "OpenCode",
  cursor: "Cursor",
};

/** All supported agent targets. */
export const ALL_AGENTS: readonly AgentTarget[] = ["claude", "opencode", "cursor"] as const;

/** Skill files that get installed (relative to skill/ root). */
export const SKILL_FILES = [
  "SKILL.md",
  "references/cli-reference.md",
  "references/output-schema.md",
  "references/workflows.md",
] as const;
