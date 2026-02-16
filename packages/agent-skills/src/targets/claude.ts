import type { InstallResult, InstallScope } from "../types.js";
import {
  copySkillFiles,
  ensureSymlink,
  globalSkillRoot,
  hasOtherGlobalSymlinks,
  removeSkillFiles,
  removeSymlink,
  resolveTargetDir,
  skillSourceDir,
} from "../utils.js";

/**
 * Install skill files for Claude Code.
 *
 * Global: copy to ~/.agents/skills/context-grabber, symlink from ~/.claude/skills/context-grabber.
 * Project: copy directly to .claude/skills/context-grabber/.
 */
export function installClaude(scope: InstallScope, cwd: string): InstallResult {
  const sourceDir = skillSourceDir();
  const symlinks: string[] = [];
  let paths: string[];

  if (scope === "global") {
    const canonical = globalSkillRoot();
    paths = copySkillFiles(sourceDir, canonical);

    const agentDir = resolveTargetDir("claude", "global", cwd);
    ensureSymlink(canonical, agentDir);
    symlinks.push(agentDir);
  } else {
    const targetDir = resolveTargetDir("claude", "project", cwd);
    paths = copySkillFiles(sourceDir, targetDir);
  }

  return { agent: "claude", scope, paths, symlinks };
}

/**
 * Uninstall skill files for Claude Code.
 */
export function uninstallClaude(scope: InstallScope, cwd: string): InstallResult {
  const symlinks: string[] = [];
  let paths: string[] = [];

  if (scope === "global") {
    const agentDir = resolveTargetDir("claude", "global", cwd);
    if (removeSymlink(agentDir)) {
      symlinks.push(agentDir);
    }

    // Only remove canonical files if no other agent symlinks still point to them.
    if (!hasOtherGlobalSymlinks("claude")) {
      const canonical = globalSkillRoot();
      paths = removeSkillFiles(canonical);
    }
  } else {
    const targetDir = resolveTargetDir("claude", "project", cwd);
    paths = removeSkillFiles(targetDir);
  }

  return { agent: "claude", scope, paths, symlinks };
}
