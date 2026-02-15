import {
  type SpawnSyncOptionsWithStringEncoding,
  type SpawnSyncReturns,
  spawnSync,
} from "node:child_process";

type SpawnSyncImpl = (
  command: string,
  args: ReadonlyArray<string>,
  options: SpawnSyncOptionsWithStringEncoding,
) => SpawnSyncReturns<string>;

type BrowserTarget = "safari" | "chrome";

const FIELD_DELIMITER = String.fromCharCode(30);
const LINE_DELIMITER = String.fromCharCode(31);
const DEFAULT_TIMEOUT_MS = 1_500;

interface ListCommandResult {
  exitCode: number;
  stdout: string;
  stderr: string;
}

interface BaseListOptions {
  env?: NodeJS.ProcessEnv;
  timeoutMs?: number;
  spawnSyncImpl?: SpawnSyncImpl;
}

export interface ListTabsOptions extends BaseListOptions {
  browser?: BrowserTarget;
}

export interface BrowserTabEntry {
  browser: BrowserTarget;
  windowIndex: number;
  tabIndex: number;
  isActive: boolean;
  title: string;
  url: string;
}

export interface DesktopAppEntry {
  appName: string;
  bundleIdentifier: string;
  windowCount: number;
}

const resolveOsaScriptBinary = (env: NodeJS.ProcessEnv): string => {
  const override = env.CONTEXT_GRABBER_OSASCRIPT_BIN;
  if (override && override.trim().length > 0) {
    return override.trim();
  }
  return "osascript";
};

const runAppleScript = (
  script: string,
  options: BaseListOptions,
): { stdout: string; stderr: string } => {
  const env = options.env ?? process.env;
  const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const spawnProcess = options.spawnSyncImpl ?? spawnSync;
  const binary = resolveOsaScriptBinary(env);

  const spawnOptions: SpawnSyncOptionsWithStringEncoding = {
    env,
    encoding: "utf8",
    input: script,
    timeout: timeoutMs,
    maxBuffer: 4 * 1024 * 1024,
  };

  const result = spawnProcess(binary, ["-"], spawnOptions);
  if (result.error) {
    const errno = result.error as NodeJS.ErrnoException;
    if (errno.code === "ETIMEDOUT") {
      throw new Error("ERR_TIMEOUT");
    }
    throw result.error;
  }

  if (result.status !== 0) {
    const stderr = (result.stderr ?? "").trim();
    throw new Error(stderr.length > 0 ? stderr : "AppleScript command failed.");
  }

  return {
    stdout: result.stdout ?? "",
    stderr: result.stderr ?? "",
  };
};

const parseBoolean = (value: string): boolean => {
  return value.trim().toLowerCase() === "true";
};

const parseTabsOutput = (browser: BrowserTarget, stdout: string): BrowserTabEntry[] => {
  const trimmed = stdout.trim();
  if (trimmed.length === 0) {
    return [];
  }

  const lines = trimmed.split(LINE_DELIMITER);
  const tabs: BrowserTabEntry[] = [];

  for (const line of lines) {
    if (!line) {
      continue;
    }
    const parts = line.split(FIELD_DELIMITER);
    if (parts.length !== 5) {
      continue;
    }

    const windowIndex = Number.parseInt(parts[0] ?? "", 10);
    const tabIndex = Number.parseInt(parts[1] ?? "", 10);
    if (!Number.isFinite(windowIndex) || !Number.isFinite(tabIndex)) {
      continue;
    }

    tabs.push({
      browser,
      windowIndex,
      tabIndex,
      isActive: parseBoolean(parts[2] ?? ""),
      title: parts[3] ?? "",
      url: parts[4] ?? "",
    });
  }

  return tabs;
};

const parseAppsOutput = (stdout: string): DesktopAppEntry[] => {
  const trimmed = stdout.trim();
  if (trimmed.length === 0) {
    return [];
  }

  const lines = trimmed.split(LINE_DELIMITER);
  const apps: DesktopAppEntry[] = [];

  for (const line of lines) {
    if (!line) {
      continue;
    }
    const parts = line.split(FIELD_DELIMITER);
    if (parts.length !== 3) {
      continue;
    }

    const windowCount = Number.parseInt(parts[2] ?? "", 10);
    if (!Number.isFinite(windowCount)) {
      continue;
    }

    apps.push({
      appName: parts[0] ?? "",
      bundleIdentifier: parts[1] ?? "",
      windowCount,
    });
  }

  return apps;
};

const sanitizeAppleScriptText = `
on sanitizeText(rawValue)
  set text item delimiters to {return, linefeed, tab, "${FIELD_DELIMITER}", "${LINE_DELIMITER}"}
  set flattenedParts to text items of (rawValue as text)
  set text item delimiters to " "
  set flattenedText to flattenedParts as text
  set text item delimiters to ""
  return flattenedText
end sanitizeText
`;

const safariTabsScript = `
${sanitizeAppleScriptText}
if application "Safari" is not running then
  return ""
end if

set outputLines to {}
tell application "Safari"
  repeat with windowIndex from 1 to (count of windows)
    set currentWindow to window windowIndex
    set activeTabIndex to index of current tab of currentWindow
    repeat with tabIndex from 1 to (count of tabs of currentWindow)
      set currentTab to tab tabIndex of currentWindow
      set tabTitle to my sanitizeText(name of currentTab)
      set tabURL to my sanitizeText(URL of currentTab)
      set isActive to tabIndex is equal to activeTabIndex
      set end of outputLines to (windowIndex as text) & "${FIELD_DELIMITER}" & (tabIndex as text) & "${FIELD_DELIMITER}" & (isActive as text) & "${FIELD_DELIMITER}" & tabTitle & "${FIELD_DELIMITER}" & tabURL
    end repeat
  end repeat
end tell

set text item delimiters to "${LINE_DELIMITER}"
set joinedLines to outputLines as text
set text item delimiters to ""
return joinedLines
`;

const chromeTabsScript = `
${sanitizeAppleScriptText}
if application "Google Chrome" is not running then
  return ""
end if

set outputLines to {}
tell application "Google Chrome"
  repeat with windowIndex from 1 to (count of windows)
    set currentWindow to window windowIndex
    set activeTabIndex to active tab index of currentWindow
    repeat with tabIndex from 1 to (count of tabs of currentWindow)
      set currentTab to tab tabIndex of currentWindow
      set tabTitle to my sanitizeText(title of currentTab)
      set tabURL to my sanitizeText(URL of currentTab)
      set isActive to tabIndex is equal to activeTabIndex
      set end of outputLines to (windowIndex as text) & "${FIELD_DELIMITER}" & (tabIndex as text) & "${FIELD_DELIMITER}" & (isActive as text) & "${FIELD_DELIMITER}" & tabTitle & "${FIELD_DELIMITER}" & tabURL
    end repeat
  end repeat
end tell

set text item delimiters to "${LINE_DELIMITER}"
set joinedLines to outputLines as text
set text item delimiters to ""
return joinedLines
`;

const appsScript = `
${sanitizeAppleScriptText}
tell application "System Events"
  set outputLines to {}
  repeat with processRef in (application processes where background only is false)
    set appName to my sanitizeText(name of processRef)
    set bundleIdentifierText to ""
    try
      set bundleIdentifierText to my sanitizeText(bundle identifier of processRef)
    end try
    set processWindowCount to 0
    try
      set processWindowCount to count of windows of processRef
    end try
    if processWindowCount > 0 then
      set end of outputLines to appName & "${FIELD_DELIMITER}" & bundleIdentifierText & "${FIELD_DELIMITER}" & (processWindowCount as text)
    end if
  end repeat
end tell

set text item delimiters to "${LINE_DELIMITER}"
set joinedLines to outputLines as text
set text item delimiters to ""
return joinedLines
`;

const resolveTabTargets = (options: ListTabsOptions): BrowserTarget[] => {
  if (options.browser) {
    return [options.browser];
  }

  const env = options.env ?? process.env;
  const envTarget = env.CONTEXT_GRABBER_BROWSER_TARGET;
  if (envTarget === "safari" || envTarget === "chrome") {
    return [envTarget];
  }

  return ["safari", "chrome"];
};

export const runListTabs = async (options: ListTabsOptions = {}): Promise<ListCommandResult> => {
  const targets = resolveTabTargets(options);
  const warnings: string[] = [];
  let tabs: BrowserTabEntry[] = [];

  for (const target of targets) {
    try {
      const script = target === "safari" ? safariTabsScript : chromeTabsScript;
      const output = runAppleScript(script, options);
      tabs = tabs.concat(parseTabsOutput(target, output.stdout));
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown error";
      warnings.push(`${target}: ${message}`);
    }
  }

  tabs.sort((left, right) => {
    if (left.browser !== right.browser) {
      return left.browser.localeCompare(right.browser);
    }
    if (left.windowIndex !== right.windowIndex) {
      return left.windowIndex - right.windowIndex;
    }
    return left.tabIndex - right.tabIndex;
  });

  const allFailed = warnings.length === targets.length;
  return {
    exitCode: allFailed ? 1 : 0,
    stdout: `${JSON.stringify(tabs, null, 2)}\n`,
    stderr: warnings.length > 0 ? `${warnings.join("\n")}\n` : "",
  };
};

export const runListApps = async (options: BaseListOptions = {}): Promise<ListCommandResult> => {
  try {
    const output = runAppleScript(appsScript, options);
    const apps = parseAppsOutput(output.stdout).sort((left, right) => {
      if (left.appName !== right.appName) {
        return left.appName.localeCompare(right.appName);
      }
      return left.bundleIdentifier.localeCompare(right.bundleIdentifier);
    });
    return {
      exitCode: 0,
      stdout: `${JSON.stringify(apps, null, 2)}\n`,
      stderr: "",
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return {
      exitCode: 1,
      stdout: "",
      stderr: `list apps failed: ${message}\n`,
    };
  }
};
