import { ALL_AGENTS, type AgentTarget, type InstallScope } from "./types.js";

export interface InstallerCliArgs {
  readonly isUninstall: boolean;
  readonly agents?: readonly AgentTarget[];
  readonly scope?: InstallScope;
  readonly assumeYes: boolean;
  readonly showHelp: boolean;
}

const AGENTS_SET = new Set<AgentTarget>(ALL_AGENTS);

function normalizeAgents(rawValues: readonly string[]): readonly AgentTarget[] {
  const seen = new Set<AgentTarget>();
  const parsed: AgentTarget[] = [];

  for (const raw of rawValues) {
    for (const part of raw.split(",")) {
      const value = part.trim().toLowerCase();
      if (!value) continue;
      if (!AGENTS_SET.has(value as AgentTarget)) {
        throw new Error(
          `Unsupported agent "${part.trim()}" (expected one of: ${ALL_AGENTS.join(", ")})`,
        );
      }
      const agent = value as AgentTarget;
      if (seen.has(agent)) continue;
      seen.add(agent);
      parsed.push(agent);
    }
  }

  return parsed;
}

function parseScope(value: string): InstallScope {
  const normalized = value.trim().toLowerCase();
  if (normalized === "global" || normalized === "project") {
    return normalized;
  }
  throw new Error(`Unsupported scope "${value}" (expected "global" or "project")`);
}

/** Parse installer CLI args used by bunx and cgrab delegation paths. */
export function parseInstallerCliArgs(argv: readonly string[]): InstallerCliArgs {
  let isUninstall = false;
  let scope: InstallScope | undefined;
  let assumeYes = false;
  let showHelp = false;
  const rawAgents: string[] = [];

  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token) continue;
    if (token === "--help" || token === "-h") {
      showHelp = true;
      continue;
    }
    if (token === "--uninstall") {
      isUninstall = true;
      continue;
    }
    if (token === "--yes" || token === "-y") {
      assumeYes = true;
      continue;
    }
    if (token === "--agent") {
      const value = argv[i + 1];
      if (!value) {
        throw new Error("Missing value for --agent");
      }
      rawAgents.push(value);
      i += 1;
      continue;
    }
    if (token.startsWith("--agent=")) {
      rawAgents.push(token.slice("--agent=".length));
      continue;
    }
    if (token === "--scope") {
      const value = argv[i + 1];
      if (!value) {
        throw new Error("Missing value for --scope");
      }
      scope = parseScope(value);
      i += 1;
      continue;
    }
    if (token.startsWith("--scope=")) {
      scope = parseScope(token.slice("--scope=".length));
      continue;
    }

    throw new Error(`Unknown argument: ${token}`);
  }

  const agents = rawAgents.length > 0 ? normalizeAgents(rawAgents) : undefined;
  return {
    isUninstall,
    assumeYes,
    showHelp,
    ...(agents ? { agents } : {}),
    ...(scope ? { scope } : {}),
  };
}
