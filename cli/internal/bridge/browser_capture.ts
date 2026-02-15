import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { env, stderr, stdout } from "node:process";
import {
  type BrowserCaptureAttempt,
  type BrowserCaptureMetadata,
  requestBrowserCapture,
} from "@context-grabber/native-host-bridge";
import type { HostRequestMessage } from "@context-grabber/shared-types";

type BrowserTarget = "safari" | "chrome";
type BrowserSourceMode = "auto" | "live" | "runtime";

interface ParsedArgs {
  target: BrowserTarget;
  source: BrowserSourceMode;
  timeoutMs: number;
  requestId: string;
  mode: "manual_menu" | "manual_hotkey";
  title?: string;
  url?: string;
  siteName?: string;
  chromeAppName?: string;
}

const repoMarkerPath = join("packages", "shared-types", "package.json");

const parseArgs = (argv: string[]): ParsedArgs => {
  const values = new Map<string, string>();
  for (let i = 0; i < argv.length; i += 1) {
    const key = argv[i];
    if (!key || !key.startsWith("--")) {
      continue;
    }

    const value = argv[i + 1];
    if (!value || value.startsWith("--")) {
      throw new Error(`Missing value for ${key}`);
    }
    values.set(key, value);
    i += 1;
  }

  const targetRaw = values.get("--target");
  if (targetRaw !== "safari" && targetRaw !== "chrome") {
    throw new Error('Expected --target to be "safari" or "chrome".');
  }

  const sourceRaw = values.get("--source") ?? "auto";
  if (sourceRaw !== "auto" && sourceRaw !== "live" && sourceRaw !== "runtime") {
    throw new Error('Expected --source to be "auto", "live", or "runtime".');
  }

  const timeoutRaw = values.get("--timeout-ms") ?? "1200";
  const timeoutMs = Number.parseInt(timeoutRaw, 10);
  if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) {
    throw new Error("Expected --timeout-ms to be a positive integer.");
  }

  const modeRaw = values.get("--mode") ?? "manual_menu";
  if (modeRaw !== "manual_menu" && modeRaw !== "manual_hotkey") {
    throw new Error('Expected --mode to be "manual_menu" or "manual_hotkey".');
  }

  return {
    target: targetRaw,
    source: sourceRaw,
    timeoutMs,
    requestId: values.get("--request-id") ?? crypto.randomUUID().toLowerCase(),
    mode: modeRaw,
    title: values.get("--title"),
    url: values.get("--url"),
    siteName: values.get("--site-name"),
    chromeAppName: values.get("--chrome-app-name"),
  };
};

const resolveRepoRoot = (): string => {
  const explicit = env.CONTEXT_GRABBER_REPO_ROOT?.trim();
  if (explicit) {
    const candidate = resolve(explicit);
    if (existsSync(join(candidate, repoMarkerPath))) {
      return candidate;
    }
    throw new Error(`CONTEXT_GRABBER_REPO_ROOT is set but invalid: ${explicit}`);
  }

  let current = resolve(process.cwd());
  for (let depth = 0; depth < 12; depth += 1) {
    if (existsSync(join(current, repoMarkerPath))) {
      return current;
    }
    const parent = dirname(current);
    if (parent === current) {
      break;
    }
    current = parent;
  }

  throw new Error("Unable to resolve repository root.");
};

const parseLastJsonLine = (text: string): unknown => {
  const lines = text
    .split(/\r?\n/g)
    .map((line) => line.trim())
    .filter((line) => line.length > 0);
  if (lines.length === 0) {
    throw new Error("Native messaging CLI returned no JSON output.");
  }
  return JSON.parse(lines[lines.length - 1] ?? "{}") as unknown;
};

const sendCaptureRequest = (
  repoRoot: string,
  args: ParsedArgs,
  request: HostRequestMessage,
): unknown => {
  const packagePath = join(
    repoRoot,
    args.target === "safari" ? "packages/extension-safari" : "packages/extension-chrome",
  );
  const cliPath = join(packagePath, "src", "native-messaging-cli.ts");
  if (!existsSync(cliPath)) {
    throw new Error(`Native messaging CLI not found: ${cliPath}`);
  }

  const runEnv: NodeJS.ProcessEnv = {
    ...env,
    CONTEXT_GRABBER_REPO_ROOT: repoRoot,
  };
  if (args.target === "safari") {
    runEnv.CONTEXT_GRABBER_SAFARI_SOURCE = args.source;
  } else {
    runEnv.CONTEXT_GRABBER_CHROME_SOURCE = args.source;
    if (args.chromeAppName && args.chromeAppName.length > 0) {
      runEnv.CONTEXT_GRABBER_CHROME_APP_NAME = args.chromeAppName;
    }
  }

  const bunBinary = env.CONTEXT_GRABBER_BUN_BIN?.trim() || process.execPath;
  const result = spawnSync(bunBinary, [cliPath], {
    cwd: packagePath,
    encoding: "utf8",
    timeout: args.timeoutMs,
    input: JSON.stringify(request),
    maxBuffer: 4 * 1024 * 1024,
    env: runEnv,
  });

  if (result.error) {
    const errorCode = (result.error as NodeJS.ErrnoException).code;
    if (errorCode === "ETIMEDOUT") {
      throw new Error("ERR_TIMEOUT");
    }
    throw result.error;
  }

  const stdoutText = result.stdout ?? "";
  const stderrText = (result.stderr ?? "").trim();
  if (stdoutText.trim().length === 0) {
    throw new Error(
      stderrText.length > 0
        ? `Native messaging bridge produced no output: ${stderrText}`
        : "Native messaging bridge produced no output.",
    );
  }

  return parseLastJsonLine(stdoutText);
};

const main = async (): Promise<void> => {
  const args = parseArgs(process.argv.slice(2));
  const repoRoot = resolveRepoRoot();
  const metadata: BrowserCaptureMetadata = {
    browser: args.target,
    title: args.title ?? (args.target === "safari" ? "Safari (focused)" : "Chrome (focused)"),
  };
  if (args.url && args.url.length > 0) {
    metadata.url = args.url;
  }
  if (args.siteName && args.siteName.length > 0) {
    metadata.siteName = args.siteName;
  }

  const attempt: BrowserCaptureAttempt = await requestBrowserCapture({
    requestId: args.requestId,
    mode: args.mode,
    timeoutMs: args.timeoutMs,
    metadata,
    send: async (request: HostRequestMessage) => {
      return sendCaptureRequest(repoRoot, args, request);
    },
    now: () => new Date().toISOString(),
    includeSelectionText: true,
  });

  stdout.write(`${JSON.stringify(attempt)}\n`);
};

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  stderr.write(`${message}\n`);
  process.exitCode = 1;
});
