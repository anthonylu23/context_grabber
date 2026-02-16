import {
  cpSync,
  existsSync,
  lstatSync,
  mkdirSync,
  readlinkSync,
  rmSync,
  symlinkSync,
} from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { type AgentTarget, type InstallScope, SKILL_FILES } from "./types.js";

/** Resolve the directory containing bundled skill files (sibling to src/). */
export function skillSourceDir(): string {
  // When run via `bun run` or `bunx`, __dirname points to src/.
  // Skill files live at ../skill/ relative to this file.
  return resolve(dirname(new URL(import.meta.url).pathname), "..", "skill");
}

/** Canonical global skill root (~/.agents/skills/context-grabber). */
export function globalSkillRoot(): string {
  return join(homedir(), ".agents", "skills", "context-grabber");
}

/**
 * Resolve the install target directory for a given agent and scope.
 *
 * Global installs use ~/.agents/skills/context-grabber as canonical location
 * with symlinks into each agent's skill directory.
 *
 * Project installs write directly into the project's agent skill directory.
 */
export function resolveTargetDir(agent: AgentTarget, scope: InstallScope, cwd: string): string {
  if (scope === "project") {
    switch (agent) {
      case "claude":
        return join(cwd, ".claude", "skills", "context-grabber");
      case "opencode":
        return join(cwd, ".opencode", "skills", "context-grabber");
      case "cursor":
        return join(cwd, ".cursor", "rules");
    }
  }

  // Global scope — return the agent-specific directory where the symlink points.
  // The canonical files go to globalSkillRoot(), symlinks go here.
  switch (agent) {
    case "claude":
      return join(homedir(), ".claude", "skills", "context-grabber");
    case "opencode":
      return join(homedir(), ".config", "opencode", "skills", "context-grabber");
    case "cursor":
      return join(homedir(), ".cursor", "rules");
  }
}

/**
 * Copy skill files from source to target directory.
 * Returns the list of created file paths.
 */
export function copySkillFiles(sourceDir: string, targetDir: string): string[] {
  const created: string[] = [];

  for (const relPath of SKILL_FILES) {
    const src = join(sourceDir, relPath);
    const dest = join(targetDir, relPath);

    if (!existsSync(src)) {
      throw new Error(`Skill source file not found: ${src}`);
    }

    mkdirSync(dirname(dest), { recursive: true });
    cpSync(src, dest, { force: true });
    created.push(dest);
  }

  return created;
}

/**
 * Create a symlink from linkPath -> targetPath.
 * If linkPath already exists as a symlink pointing to the same target, skip.
 * If it exists as something else, remove and recreate.
 */
export function ensureSymlink(targetPath: string, linkPath: string): void {
  try {
    const stat = lstatSync(linkPath);
    if (stat.isSymbolicLink()) {
      const current = readlinkSync(linkPath);
      if (resolve(current) === resolve(targetPath)) {
        return; // Already correct.
      }
    }
    // Wrong target or not a symlink — remove.
    rmSync(linkPath, { recursive: true, force: true });
  } catch {
    // Path doesn't exist — proceed to create.
  }

  mkdirSync(dirname(linkPath), { recursive: true });
  symlinkSync(targetPath, linkPath);
}

/**
 * Remove installed skill files from a target directory.
 * Returns the list of removed file paths.
 *
 * @param skipDirCleanup If true, don't remove the target directory itself after
 *   removing files. Used for Cursor's shared `.cursor/rules/` directory.
 */
export function removeSkillFiles(targetDir: string, skipDirCleanup = false): string[] {
  const removed: string[] = [];

  for (const relPath of SKILL_FILES) {
    const filePath = join(targetDir, relPath);
    if (existsSync(filePath)) {
      rmSync(filePath);
      removed.push(filePath);
    }
  }

  // Clean up empty references/ subdirectory if we created it.
  const refsDir = join(targetDir, "references");
  if (existsSync(refsDir)) {
    try {
      rmSync(refsDir, { recursive: false });
    } catch {
      // Not empty — other files present, leave it.
    }
  }

  // Clean up the target directory itself if empty, unless caller opted out.
  if (!skipDirCleanup && existsSync(targetDir)) {
    try {
      rmSync(targetDir, { recursive: false });
    } catch {
      // Not empty — leave it.
    }
  }

  return removed;
}

/**
 * Remove a symlink if it exists and points to globalSkillRoot().
 */
export function removeSymlink(linkPath: string): boolean {
  try {
    const stat = lstatSync(linkPath);
    if (!stat.isSymbolicLink()) return false;

    const target = readlinkSync(linkPath);
    if (resolve(target) === resolve(globalSkillRoot())) {
      rmSync(linkPath);
      return true;
    }
  } catch {
    // Path doesn't exist or can't be read — nothing to remove.
  }

  return false;
}

/** All agents that use global symlinks (not Cursor — it has no global symlink). */
const SYMLINK_AGENTS: AgentTarget[] = ["claude", "opencode"];

/**
 * Check whether any agent other than `excludeAgent` still has a global symlink
 * pointing to the canonical skill root.
 *
 * Used during global uninstall to decide whether canonical files can be safely
 * removed: if another agent still references them, we must leave them in place.
 */
export function hasOtherGlobalSymlinks(excludeAgent: AgentTarget): boolean {
  const canonical = globalSkillRoot();

  for (const agent of SYMLINK_AGENTS) {
    if (agent === excludeAgent) continue;

    const agentDir = resolveTargetDir(agent, "global", "");
    try {
      const stat = lstatSync(agentDir);
      if (!stat.isSymbolicLink()) continue;

      const target = readlinkSync(agentDir);
      if (resolve(target) === resolve(canonical)) {
        return true; // Another agent still points here.
      }
    } catch {
      // Doesn't exist or not a symlink — skip.
    }
  }

  return false;
}
