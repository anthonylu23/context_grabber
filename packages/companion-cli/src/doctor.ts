import type { BridgeClient, BrowserTarget } from "./native-bridge.js";

interface DoctorResult {
  exitCode: number;
  output: string;
}

const TARGETS: BrowserTarget[] = ["safari", "chrome"];

export const runDoctor = async (bridge: BridgeClient): Promise<DoctorResult> => {
  const statuses = await Promise.all(
    TARGETS.map(async (target) => {
      const status = await bridge.ping(target);
      return {
        target,
        status,
      };
    }),
  );

  const readyCount = statuses.filter((entry) => entry.status.state === "ready").length;
  const output = [
    "Context Grabber diagnostics",
    ...statuses.map((entry) => `${entry.target}: ${entry.status.label}`),
    `overall: ${readyCount > 0 ? "ready" : "unreachable"}`,
  ].join("\n");

  return {
    exitCode: readyCount > 0 ? 0 : 1,
    output,
  };
};
