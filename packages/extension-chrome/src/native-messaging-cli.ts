import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { stdin as input, stdout as output } from "node:process";
import { fileURLToPath } from "node:url";
import { type HostRequestMessage, PROTOCOL_VERSION } from "@context-grabber/shared-types";
import type { ChromeExtractionInput } from "./index.js";
import { type HostRequestHandlingOptions, handleHostCaptureRequest } from "./transport.js";

interface PingResult {
  ok: true;
  protocolVersion: string;
}

type ChromeSourceMode = "auto" | "runtime" | "fixture";

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

const loadFixtureFromDisk = async (): Promise<ChromeExtractionInput> => {
  const envFixturePath = process.env.CONTEXT_GRABBER_CHROME_FIXTURE_PATH;
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
  return JSON.parse(raw) as ChromeExtractionInput;
};

const loadRuntimePayload = async (): Promise<ChromeExtractionInput> => {
  const inlinePayload = process.env.CONTEXT_GRABBER_CHROME_RUNTIME_PAYLOAD;
  if (inlinePayload && inlinePayload.length > 0) {
    return JSON.parse(inlinePayload) as ChromeExtractionInput;
  }

  const payloadPath = process.env.CONTEXT_GRABBER_CHROME_RUNTIME_PAYLOAD_PATH;
  if (payloadPath && payloadPath.length > 0) {
    if (!existsSync(payloadPath)) {
      throw new Error(`Runtime payload file not found at ${payloadPath}`);
    }

    const raw = await readFile(payloadPath, "utf8");
    return JSON.parse(raw) as ChromeExtractionInput;
  }

  throw new Error(
    "Runtime source requires CONTEXT_GRABBER_CHROME_RUNTIME_PAYLOAD or CONTEXT_GRABBER_CHROME_RUNTIME_PAYLOAD_PATH.",
  );
};

const resolveSourceMode = (): ChromeSourceMode => {
  const mode = process.env.CONTEXT_GRABBER_CHROME_SOURCE;
  if (mode === "runtime" || mode === "fixture" || mode === "auto") {
    return mode;
  }

  if (typeof mode === "string" && mode.length > 0) {
    throw new Error(`Unsupported CONTEXT_GRABBER_CHROME_SOURCE mode: ${mode}`);
  }

  return "auto";
};

const resolveCaptureSource = async (): Promise<ChromeExtractionInput> => {
  const mode = resolveSourceMode();

  if (mode === "fixture") {
    return loadFixtureFromDisk();
  }

  return loadRuntimePayload();
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
    async (_hostRequest: HostRequestMessage) => {
      return resolveCaptureSource();
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
