export interface CaptureFocusedCommand {
  kind: "capture-focused";
}

export interface DoctorCommand {
  kind: "doctor";
}

export interface ListTabsCommand {
  kind: "list-tabs";
  browser?: "safari" | "chrome";
}

export interface ListAppsCommand {
  kind: "list-apps";
}

export interface HelpCommand {
  kind: "help";
}

export type CompanionCommand =
  | CaptureFocusedCommand
  | DoctorCommand
  | ListTabsCommand
  | ListAppsCommand
  | HelpCommand;

export type ParseCommandResult =
  | { ok: true; command: CompanionCommand }
  | { ok: false; error: string };

const HELP_FLAGS = new Set(["help", "--help", "-h"]);

export const parseCompanionCommand = (argv: string[]): ParseCommandResult => {
  const args = argv.filter((arg) => arg.trim().length > 0);
  if (args.length === 0) {
    return {
      ok: true,
      command: { kind: "help" },
    };
  }

  const first = args[0];
  const rest = args.slice(1);
  if (!first) {
    return {
      ok: true,
      command: { kind: "help" },
    };
  }
  if (HELP_FLAGS.has(first)) {
    return {
      ok: true,
      command: { kind: "help" },
    };
  }

  if (first === "doctor") {
    if (rest.length > 0) {
      return {
        ok: false,
        error: `doctor does not accept extra arguments: ${rest.join(" ")}`,
      };
    }

    return {
      ok: true,
      command: { kind: "doctor" },
    };
  }

  if (first === "capture") {
    if (rest.length === 1 && rest[0] === "--focused") {
      return {
        ok: true,
        command: { kind: "capture-focused" },
      };
    }

    return {
      ok: false,
      error: "capture currently supports only: capture --focused",
    };
  }

  if (first === "list") {
    const subject = rest[0];
    if (!subject) {
      return {
        ok: false,
        error: "list requires a subject: tabs or apps",
      };
    }

    const tail = rest.slice(1);
    if (subject === "tabs") {
      if (tail.length === 0) {
        return {
          ok: true,
          command: { kind: "list-tabs" },
        };
      }

      if (
        tail.length === 2 &&
        tail[0] === "--browser" &&
        (tail[1] === "safari" || tail[1] === "chrome")
      ) {
        return {
          ok: true,
          command: { kind: "list-tabs", browser: tail[1] },
        };
      }

      return {
        ok: false,
        error: "list tabs supports optional: --browser safari|chrome",
      };
    }

    if (subject === "apps") {
      if (tail.length > 0) {
        return {
          ok: false,
          error: `list apps does not accept extra arguments: ${tail.join(" ")}`,
        };
      }

      return {
        ok: true,
        command: { kind: "list-apps" },
      };
    }

    return {
      ok: false,
      error: `Unsupported list subject: ${subject}`,
    };
  }

  return {
    ok: false,
    error: `Unknown command: ${first}`,
  };
};

export const companionUsage = (): string => {
  return [
    "Context Grabber companion CLI",
    "",
    "Usage:",
    "  context-grabber doctor",
    "  context-grabber capture --focused",
    "  context-grabber list tabs [--browser safari|chrome]",
    "  context-grabber list apps",
    "",
    "Environment:",
    "  CONTEXT_GRABBER_REPO_ROOT       Optional repo root override.",
    "  CONTEXT_GRABBER_BUN_BIN         Optional Bun binary override.",
    "  CONTEXT_GRABBER_BROWSER_TARGET  Optional browser target override (safari|chrome).",
    "  CONTEXT_GRABBER_OSASCRIPT_BIN   Optional osascript binary override.",
  ].join("\n");
};
