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
 * Install skill files for OpenCode.
 *
 * Global: copy to ~/.agents/skills/context-grabber, symlink from ~/.config/opencode/skills/context-grabber.
 * Project: copy directly to .opencode/skills/context-grabber/.
 */
export function installOpenCode(scope: InstallScope, cwd: string): InstallResult {
  const sourceDir = skillSourceDir();
  const symlinks: string[] = [];
  let paths: string[];

  if (scope === "global") {
    const canonical = globalSkillRoot();
    paths = copySkillFiles(sourceDir, canonical);

    const agentDir = resolveTargetDir("opencode", "global", cwd);
    ensureSymlink(canonical, agentDir);
    symlinks.push(agentDir);
  } else {
    const targetDir = resolveTargetDir("opencode", "project", cwd);
    paths = copySkillFiles(sourceDir, targetDir);
  }

  return { agent: "opencode", scope, paths, symlinks };
}

/**
 * Uninstall skill files for OpenCode.
 */
export function uninstallOpenCode(scope: InstallScope, cwd: string): InstallResult {
  const symlinks: string[] = [];
  let paths: string[] = [];

  if (scope === "global") {
    const agentDir = resolveTargetDir("opencode", "global", cwd);
    if (removeSymlink(agentDir)) {
      symlinks.push(agentDir);
    }

    // Only remove canonical files if no other agent symlinks still point to them.
    if (!hasOtherGlobalSymlinks("opencode")) {
      const canonical = globalSkillRoot();
      paths = removeSkillFiles(canonical);
    }
  } else {
    const targetDir = resolveTargetDir("opencode", "project", cwd);
    paths = removeSkillFiles(targetDir);
  }

  return { agent: "opencode", scope, paths, symlinks };
}
