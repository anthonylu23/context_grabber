import { installClaude, uninstallClaude } from "./targets/claude.js";
import { installCursor, uninstallCursor } from "./targets/cursor.js";
import { installOpenCode, uninstallOpenCode } from "./targets/opencode.js";
import type { AgentTarget, InstallResult, InstallScope } from "./types.js";

/** Dispatch install to the correct agent target. */
export function installForAgent(
  agent: AgentTarget,
  scope: InstallScope,
  cwd: string,
): InstallResult {
  switch (agent) {
    case "claude":
      return installClaude(scope, cwd);
    case "opencode":
      return installOpenCode(scope, cwd);
    case "cursor":
      return installCursor(scope, cwd);
  }
}

/** Dispatch uninstall to the correct agent target. */
export function uninstallForAgent(
  agent: AgentTarget,
  scope: InstallScope,
  cwd: string,
): InstallResult {
  switch (agent) {
    case "claude":
      return uninstallClaude(scope, cwd);
    case "opencode":
      return uninstallOpenCode(scope, cwd);
    case "cursor":
      return uninstallCursor(scope, cwd);
  }
}
