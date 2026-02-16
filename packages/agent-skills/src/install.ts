#!/usr/bin/env bun
import { checkbox, confirm, select } from "@inquirer/prompts";
import { installForAgent, uninstallForAgent } from "./dispatch.js";
import { AGENT_LABELS, ALL_AGENTS, type AgentTarget, type InstallScope } from "./types.js";

const isUninstall = process.argv.includes("--uninstall");
const action = isUninstall ? "uninstall" : "install";

console.log("");
console.log("Context Grabber — Agent Skill Installer");
console.log("");

try {
  // Step 1: Select agents.
  const agents = await checkbox<AgentTarget>({
    message: `Which agents do you want to ${action} for?`,
    choices: ALL_AGENTS.map((agent) => ({
      name: AGENT_LABELS[agent],
      value: agent,
      checked: agent === "claude",
    })),
    required: true,
  });

  if (agents.length === 0) {
    console.log("No agents selected. Exiting.");
    process.exit(0);
  }

  // Step 2: Select scope.
  const scope = await select<InstallScope>({
    message: "Install scope?",
    choices: [
      {
        name: "Global — available in all projects",
        value: "global" as const,
      },
      {
        name: "Project — this project only",
        value: "project" as const,
      },
    ],
    default: "global",
  });

  // Step 3: Confirm.
  const agentNames = agents.map((a) => AGENT_LABELS[a]).join(", ");
  const shouldProceed = await confirm({
    message: `${isUninstall ? "Uninstall from" : "Install for"} ${agentNames} (${scope} scope)?`,
    default: true,
  });

  if (!shouldProceed) {
    console.log("Cancelled.");
    process.exit(0);
  }

  // Step 4: Execute.
  const cwd = process.cwd();

  console.log("");
  for (const agent of agents) {
    const label = AGENT_LABELS[agent];
    console.log(
      `${isUninstall ? "Uninstalling from" : "Installing for"} ${label} (${scope} scope)...`,
    );

    const result = isUninstall
      ? uninstallForAgent(agent, scope, cwd)
      : installForAgent(agent, scope, cwd);

    for (const path of result.paths) {
      console.log(`  ${isUninstall ? "Removed" : "Created"} ${path}`);
    }
    for (const symlink of result.symlinks) {
      console.log(`  ${isUninstall ? "Removed symlink" : "Symlinked"} ${symlink}`);
    }

    if (result.paths.length === 0 && result.symlinks.length === 0) {
      console.log(`  Nothing to ${action}.`);
    }
  }

  console.log("");
  if (isUninstall) {
    console.log("Done. Skill files removed.");
  } else {
    console.log("Done. The agent can now discover and use cgrab.");
  }
} catch (error) {
  // Handle Ctrl+C gracefully (inquirer throws on cancel).
  if (error instanceof Error && error.message.includes("User force closed")) {
    console.log("\nCancelled.");
    process.exit(0);
  }
  throw error;
}
