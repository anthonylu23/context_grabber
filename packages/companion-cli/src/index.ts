import { runCaptureFocused } from "./capture-focused.js";
import { companionUsage, parseCompanionCommand } from "./commands.js";
import { runDoctor } from "./doctor.js";
import { createBridgeClient } from "./native-bridge.js";

const writeStdout = (text: string): void => {
  if (text.length > 0) {
    process.stdout.write(text);
  }
};

const writeStderr = (text: string): void => {
  if (text.length > 0) {
    process.stderr.write(text);
  }
};

const main = async (): Promise<void> => {
  const parsed = parseCompanionCommand(process.argv.slice(2));
  if (!parsed.ok) {
    writeStderr(`${parsed.error}\n\n${companionUsage()}\n`);
    process.exitCode = 1;
    return;
  }

  if (parsed.command.kind === "help") {
    writeStdout(`${companionUsage()}\n`);
    return;
  }

  const bridge = createBridgeClient();

  if (parsed.command.kind === "doctor") {
    const doctorResult = await runDoctor(bridge);
    writeStdout(`${doctorResult.output}\n`);
    process.exitCode = doctorResult.exitCode;
    return;
  }

  const captureResult = await runCaptureFocused({
    bridge,
  });
  writeStdout(captureResult.stdout);
  writeStderr(captureResult.stderr);
  process.exitCode = captureResult.exitCode;
};

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : "Unknown CLI error.";
  writeStderr(`${message}\n`);
  process.exitCode = 1;
});
