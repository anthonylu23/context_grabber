import { cpSync, existsSync, mkdirSync, readlinkSync, rmSync, symlinkSync } from "node:fs";
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
  if (existsSync(linkPath)) {
    try {
      const current = readlinkSync(linkPath);
      if (resolve(current) === resolve(targetPath)) {
        return; // Already correct.
      }
    } catch {
      // Not a symlink — remove it.
    }
    rmSync(linkPath, { recursive: true, force: true });
  }

  mkdirSync(dirname(linkPath), { recursive: true });
  symlinkSync(targetPath, linkPath);
}

/**
 * Remove installed skill files from a target directory.
 * Returns the list of removed file paths.
 */
export function removeSkillFiles(targetDir: string): string[] {
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

  // Clean up the target directory itself if empty (only for non-cursor agents).
  if (existsSync(targetDir) && !targetDir.endsWith("rules")) {
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
  if (!existsSync(linkPath)) return false;

  try {
    const target = readlinkSync(linkPath);
    if (resolve(target) === resolve(globalSkillRoot())) {
      rmSync(linkPath);
      return true;
    }
  } catch {
    // Not a symlink — don't remove.
  }

  return false;
}
