import {
  type SpawnSyncOptionsWithStringEncoding,
  type SpawnSyncReturns,
  spawnSync,
} from "node:child_process";
import { constants, accessSync, existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { type HostRequestMessage, PROTOCOL_VERSION } from "@context-grabber/shared-types";

export type BrowserTarget = "safari" | "chrome";

interface ProcessOutput {
  status: number;
  stdout: string;
  stderr: string;
}

interface TargetRuntime {
  packagePath: string;
  cliPath: string;
}

type SpawnSyncImpl = (
  command: string,
  args: ReadonlyArray<string>,
  options: SpawnSyncOptionsWithStringEncoding,
) => SpawnSyncReturns<string>;

const REPO_MARKER = "packages/shared-types/package.json";

const TARGET_PACKAGE_PATH: Record<BrowserTarget, string> = {
  safari: "packages/extension-safari",
  chrome: "packages/extension-chrome",
};

const parseLastJsonLine = (stdout: string): unknown => {
  const lines = stdout
    .split(/\r?\n/g)
    .map((line) => line.trim())
    .filter((line) => line.length > 0);

  if (lines.length === 0) {
    throw new Error("Native messaging CLI returned no JSON output.");
  }

  return JSON.parse(lines[lines.length - 1] ?? "{}") as unknown;
};

const isNativePingResponse = (
  value: unknown,
): value is { ok: boolean; protocolVersion: string } => {
  if (typeof value !== "object" || value === null) {
    return false;
  }

  const typed = value as { ok?: unknown; protocolVersion?: unknown };
  return typeof typed.ok === "boolean" && typeof typed.protocolVersion === "string";
};

const resolveRepoRoot = (cwd: string, env: NodeJS.ProcessEnv): string => {
  const envRoot = env.CONTEXT_GRABBER_REPO_ROOT;
  if (envRoot && envRoot.length > 0) {
    const explicit = resolve(envRoot);
    if (existsSync(join(explicit, REPO_MARKER))) {
      return explicit;
    }
  }

  let current = resolve(cwd);
  for (let depth = 0; depth < 12; depth += 1) {
    if (existsSync(join(current, REPO_MARKER))) {
      return current;
    }
    const parent = dirname(current);
    if (parent === current) {
      break;
    }
    current = parent;
  }

  throw new Error("Unable to locate repository root. Set CONTEXT_GRABBER_REPO_ROOT.");
};

const resolveBunBinary = (env: NodeJS.ProcessEnv): string => {
  const configured = env.CONTEXT_GRABBER_BUN_BIN;
  if (configured && configured.length > 0) {
    accessSync(configured, constants.X_OK);
    return configured;
  }

  return process.execPath;
};

const resolveTargetRuntime = (
  target: BrowserTarget,
  cwd: string,
  env: NodeJS.ProcessEnv,
): TargetRuntime => {
  const repoRoot = resolveRepoRoot(cwd, env);
  const packagePath = join(repoRoot, TARGET_PACKAGE_PATH[target]);
  const cliPath = join(packagePath, "src/native-messaging-cli.ts");

  if (!existsSync(cliPath)) {
    throw new Error(`Native messaging CLI not found: ${cliPath}`);
  }

  return {
    packagePath,
    cliPath,
  };
};

const runNativeMessaging = (
  target: BrowserTarget,
  args: string[],
  stdinText: string | null,
  timeoutMs: number,
  cwd: string,
  env: NodeJS.ProcessEnv,
  spawnSyncImpl: SpawnSyncImpl,
): ProcessOutput => {
  const runtime = resolveTargetRuntime(target, cwd, env);
  const bunBinary = resolveBunBinary(env);

  const spawnOptions: SpawnSyncOptionsWithStringEncoding = {
    cwd: runtime.packagePath,
    encoding: "utf8",
    timeout: timeoutMs,
    input: stdinText ?? undefined,
    env,
    maxBuffer: 4 * 1024 * 1024,
  };

  const result = spawnSyncImpl(bunBinary, [runtime.cliPath, ...args], spawnOptions);

  if (result.error) {
    const errno = result.error as NodeJS.ErrnoException;
    if (errno.code === "ETIMEDOUT") {
      throw new Error("ERR_TIMEOUT");
    }
    throw result.error;
  }

  if (typeof result.status !== "number") {
    if (result.signal === "SIGTERM") {
      throw new Error("ERR_TIMEOUT");
    }
    throw new Error(`Native messaging CLI timed out for ${target}.`);
  }

  return {
    status: result.status,
    stdout: result.stdout ?? "",
    stderr: result.stderr ?? "",
  };
};

export interface BridgeClient {
  ping(
    target: BrowserTarget,
  ): Promise<{ state: "ready" | "protocol_mismatch" | "unreachable"; label: string }>;
  sendCaptureRequest(target: BrowserTarget, request: HostRequestMessage): Promise<unknown>;
}

export interface BridgeClientOptions {
  timeoutMs?: number;
  cwd?: string;
  env?: NodeJS.ProcessEnv;
  spawnSyncImpl?: SpawnSyncImpl;
}

export const createBridgeClient = (options: BridgeClientOptions = {}): BridgeClient => {
  const timeoutMs = options.timeoutMs ?? 1_200;
  const cwd = options.cwd ?? process.cwd();
  const env = options.env ?? process.env;
  const spawnProcess = options.spawnSyncImpl ?? spawnSync;

  return {
    async ping(target: BrowserTarget) {
      try {
        const output = runNativeMessaging(
          target,
          ["--ping"],
          null,
          timeoutMs,
          cwd,
          env,
          spawnProcess,
        );
        if (output.status !== 0) {
          return {
            state: "unreachable",
            label: "unreachable",
          };
        }

        const parsed = parseLastJsonLine(output.stdout);
        if (!isNativePingResponse(parsed) || parsed.ok !== true) {
          return {
            state: "unreachable",
            label: "unreachable",
          };
        }

        if (parsed.protocolVersion === PROTOCOL_VERSION) {
          return {
            state: "ready",
            label: `ready/protocol ${parsed.protocolVersion}`,
          };
        }

        return {
          state: "protocol_mismatch",
          label: `protocol mismatch (${parsed.protocolVersion})`,
        };
      } catch {
        return {
          state: "unreachable",
          label: "unreachable",
        };
      }
    },

    async sendCaptureRequest(target: BrowserTarget, request: HostRequestMessage): Promise<unknown> {
      const output = runNativeMessaging(
        target,
        [],
        JSON.stringify(request),
        request.payload.timeoutMs,
        cwd,
        env,
        spawnProcess,
      );

      if (output.stdout.trim().length === 0) {
        const stderr = output.stderr.trim();
        throw new Error(
          stderr.length > 0
            ? `${target} native messaging bridge produced no JSON output: ${stderr}`
            : `${target} native messaging bridge produced no JSON output.`,
        );
      }

      return parseLastJsonLine(output.stdout);
    },
  };
};
