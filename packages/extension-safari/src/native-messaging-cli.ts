import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { stdin as input, stdout as output } from "node:process";
import { fileURLToPath } from "node:url";
import { type HostRequestMessage, PROTOCOL_VERSION } from "@context-grabber/shared-types";
import type { SafariExtractionInput } from "./index.js";
import { type HostRequestHandlingOptions, handleHostCaptureRequest } from "./transport.js";

interface PingResult {
  ok: true;
  protocolVersion: string;
}

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

const loadFixtureFromDisk = async (): Promise<SafariExtractionInput> => {
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
  return JSON.parse(raw) as SafariExtractionInput;
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
      return await loadFixtureFromDisk();
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
