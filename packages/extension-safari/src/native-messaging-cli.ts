import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { stdin as input, stdout as output } from "node:process";
import { fileURLToPath } from "node:url";
import { type HostRequestMessage, PROTOCOL_VERSION } from "@context-grabber/shared-types";
import { extractActiveTabContextFromSafari } from "./extract-active-tab.js";
import type { SafariExtractionInput } from "./index.js";
import { toSafariExtractionInput } from "./sanitize-snapshot.js";
import { type HostRequestHandlingOptions, handleHostCaptureRequest } from "./transport.js";

interface PingResult {
  ok: true;
  protocolVersion: string;
}

type SafariSourceMode = "auto" | "runtime" | "live" | "fixture";

const readStdinText = async (): Promise<string> => {
  const bunStdin = (globalThis as { Bun?: { stdin?: { text?: () => Promise<string> } } }).Bun
    ?.stdin;

  if (bunStdin && typeof bunStdin.text === "function") {
    const buffer = await bunStdin.text();
    return buffer.trim();
  }

  let buffer = "";
  input.setEncoding("utf8");
  for await (const chunk of input) {
    buffer += chunk;
  }

  return buffer.trim();
};

const loadFixtureFromDisk = async (): Promise<unknown> => {
  const envFixturePath = process.env.CONTEXT_GRABBER_SAFARI_FIXTURE_PATH;
  const currentFilePath = fileURLToPath(import.meta.url);
  const currentDirPath = dirname(currentFilePath);
  const fixturePath =
    envFixturePath && envFixturePath.length > 0
      ? envFixturePath
      : join(currentDirPath, "..", "fixtures", "active-tab.json");

  if (!existsSync(fixturePath)) {
    throw new Error(`Fixture not found at ${fixturePath}`);
  }

  const raw = await readFile(fixturePath, "utf8");
  return JSON.parse(raw) as unknown;
};

const loadRuntimePayload = async (): Promise<unknown> => {
  const inlinePayload = process.env.CONTEXT_GRABBER_SAFARI_RUNTIME_PAYLOAD;
  if (inlinePayload && inlinePayload.length > 0) {
    return JSON.parse(inlinePayload) as unknown;
  }

  const payloadPath = process.env.CONTEXT_GRABBER_SAFARI_RUNTIME_PAYLOAD_PATH;
  if (payloadPath && payloadPath.length > 0) {
    if (!existsSync(payloadPath)) {
      throw new Error(`Runtime payload file not found at ${payloadPath}`);
    }

    const raw = await readFile(payloadPath, "utf8");
    return JSON.parse(raw) as unknown;
  }

  throw new Error(
    "Runtime source requires CONTEXT_GRABBER_SAFARI_RUNTIME_PAYLOAD or CONTEXT_GRABBER_SAFARI_RUNTIME_PAYLOAD_PATH.",
  );
};

const resolveSourceMode = (): SafariSourceMode => {
  const mode = process.env.CONTEXT_GRABBER_SAFARI_SOURCE;
  if (mode === "runtime" || mode === "live" || mode === "fixture" || mode === "auto") {
    return mode;
  }

  if (typeof mode === "string" && mode.length > 0) {
    throw new Error(`Unsupported CONTEXT_GRABBER_SAFARI_SOURCE mode: ${mode}`);
  }

  return "auto";
};

const hasConfiguredRuntimePayload = (): boolean => {
  const inlinePayload = process.env.CONTEXT_GRABBER_SAFARI_RUNTIME_PAYLOAD;
  const payloadPath = process.env.CONTEXT_GRABBER_SAFARI_RUNTIME_PAYLOAD_PATH;
  return Boolean(
    (inlinePayload && inlinePayload.length > 0) || (payloadPath && payloadPath.length > 0),
  );
};

const errorReason = (error: unknown): string => {
  if (error instanceof Error) {
    return error.message;
  }

  return String(error);
};

const buildAutoSourceFailureMessage = (liveError: unknown, runtimeError?: unknown): string => {
  const liveMessage = errorReason(liveError);
  if (runtimeError === undefined) {
    return `Auto source failed during live extraction: ${liveMessage}`;
  }

  const runtimeMessage = errorReason(runtimeError);
  return `Auto source failed. Live extraction error: ${liveMessage}. Runtime fallback error: ${runtimeMessage}`;
};

const resolveCaptureSource = async (
  hostRequest: HostRequestMessage,
): Promise<SafariExtractionInput> => {
  const mode = resolveSourceMode();
  const includeSelectionText = hostRequest.payload.includeSelectionText;

  const fromLive = (): SafariExtractionInput => {
    const osascriptBinary = process.env.CONTEXT_GRABBER_SAFARI_OSASCRIPT_BIN;
    const timeoutMs = hostRequest.payload.timeoutMs;
    return extractActiveTabContextFromSafari({
      includeSelectionText,
      timeoutMs,
      ...(osascriptBinary && osascriptBinary.length > 0 ? { osascriptBinary } : {}),
    });
  };

  const fromRuntime = async (): Promise<SafariExtractionInput> => {
    const payload = await loadRuntimePayload();
    return toSafariExtractionInput(payload, includeSelectionText);
  };

  const fromFixture = async (): Promise<SafariExtractionInput> => {
    const payload = await loadFixtureFromDisk();
    return toSafariExtractionInput(payload, includeSelectionText);
  };

  if (mode === "live") {
    return fromLive();
  }

  if (mode === "runtime") {
    return fromRuntime();
  }

  if (mode === "fixture") {
    return fromFixture();
  }

  const runtimeConfigured = hasConfiguredRuntimePayload();
  try {
    return fromLive();
  } catch (liveError) {
    if (!runtimeConfigured) {
      throw new Error(buildAutoSourceFailureMessage(liveError));
    }

    try {
      return await fromRuntime();
    } catch (runtimeError) {
      throw new Error(buildAutoSourceFailureMessage(liveError, runtimeError));
    }
  }
};

const emit = (value: unknown): void => {
  output.write(`${JSON.stringify(value)}\n`);
};

const runPing = (): void => {
  const result: PingResult = {
    ok: true,
    protocolVersion: PROTOCOL_VERSION,
  };

  emit(result);
};

const runCapture = async (options: HostRequestHandlingOptions): Promise<void> => {
  const requestText = await readStdinText();
  const request = requestText.length > 0 ? (JSON.parse(requestText) as unknown) : {};

  const response = await handleHostCaptureRequest(
    request,
    async (hostRequest: HostRequestMessage) => {
      return resolveCaptureSource(hostRequest);
    },
    options,
  );

  emit(response);
};

const main = async (): Promise<void> => {
  const args = process.argv.slice(2);

  if (args.includes("--ping")) {
    runPing();
    return;
  }

  await runCapture({
    now: () => new Date().toISOString(),
  });
};

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : "Unknown native messaging CLI error.";
  emit({
    id: crypto.randomUUID(),
    type: "extension.error",
    timestamp: new Date().toISOString(),
    payload: {
      protocolVersion: PROTOCOL_VERSION,
      code: "ERR_EXTENSION_UNAVAILABLE",
      message,
      recoverable: true,
    },
  });
  process.exitCode = 1;
});
