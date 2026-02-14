import { spawnSync } from "node:child_process";
import { readdirSync, statSync } from "node:fs";
import { join } from "node:path";

const ACTIONS = new Set(["typecheck", "test", "check"]);
const action = process.argv[2] ?? "check";

if (!ACTIONS.has(action)) {
  console.error(`Unknown action: ${action}`);
  console.error("Usage: bun run scripts/check-workspace.ts [typecheck|test|check]");
  process.exit(1);
}

const packagesDir = "packages";
const packageDirs = readdirSync(packagesDir)
  .map((entry) => join(packagesDir, entry))
  .filter((dir) => {
    try {
      return statSync(dir).isDirectory() && statSync(join(dir, "package.json")).isFile();
    } catch {
      return false;
    }
  })
  .sort();

if (packageDirs.length === 0) {
  console.error("No workspace packages found under packages/.");
  process.exit(1);
}

const runCommand = (command: string[], cwd?: string): void => {
  const [bin, ...args] = command;
  const result = spawnSync(bin, args, {
    stdio: "inherit",
    cwd,
  });

  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
};

const runForPackages = (scriptName: "typecheck" | "test"): void => {
  for (const packageDir of packageDirs) {
    console.log(`==> ${scriptName} :: ${packageDir}`);
    runCommand(["bun", "run", scriptName], packageDir);
  }
};

if (action === "typecheck") {
  runForPackages("typecheck");
  process.exit(0);
}

if (action === "test") {
  runForPackages("test");
  process.exit(0);
}

runCommand(["bun", "run", "lint"]);
runForPackages("typecheck");
runForPackages("test");
