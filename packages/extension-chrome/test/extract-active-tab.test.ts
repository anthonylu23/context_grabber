import { describe, expect, it } from "bun:test";
import { chmod, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import {
  buildChromeDocumentScript,
  extractActiveTabContextFromChrome,
  toChromeExtractionInput,
} from "../src/extract-active-tab.js";

const createFakeOsaScriptBinary = async (stdoutFilePath: string): Promise<string> => {
  const dir = await mkdtemp(join(tmpdir(), "context-grabber-osa-"));
  const binaryPath = join(dir, "fake-osascript.sh");

  await writeFile(
    binaryPath,
    ["#!/bin/sh", `cat "${stdoutFilePath}"`, "exit 0", ""].join("\n"),
    "utf8",
  );
  await chmod(binaryPath, 0o755);
  return binaryPath;
};

const createAppleScriptSpyBinary = async (outputFilePath: string): Promise<string> => {
  const dir = await mkdtemp(join(tmpdir(), "context-grabber-osa-spy-"));
  const binaryPath = join(dir, "spy-osascript.sh");

  // Writes all arguments to outputFilePath so the test can inspect what AppleScript was generated
  await writeFile(
    binaryPath,
    [
      "#!/bin/sh",
      `echo "$@" > "${outputFilePath}"`,
      // Output valid JSON so the extraction doesn't fail on parse
      'echo \'{"url":"https://example.com","title":"Test","fullText":"body","headings":[],"links":[]}\'',
      "exit 0",
      "",
    ].join("\n"),
    "utf8",
  );
  await chmod(binaryPath, 0o755);
  return binaryPath;
};

describe("chrome active-tab extraction helpers", () => {
  it("sanitizes raw snapshots into Chrome extraction payloads", () => {
    const payload = toChromeExtractionInput(
      {
        url: "https://example.com/docs",
        title: "Example Docs",
        fullText: "  Intro section.\n\n\nMore details.  ",
        headings: [
          { level: 1, text: "  Heading  " },
          { level: 8, text: "Ignored" },
          { level: 2, text: "Details" },
        ],
        links: [
          { text: " Docs ", href: "https://example.com/docs" },
          { text: "Docs", href: "https://example.com/docs" },
          { text: "", href: "https://example.com/blank" },
        ],
        selectionText: " Selected line ",
        metaDescription: "description",
      },
      true,
    );

    expect(payload.url).toBe("https://example.com/docs");
    expect(payload.title).toBe("Example Docs");
    expect(payload.fullText).toBe("Intro section.\n\nMore details.");
    expect((payload.headings ?? []).length).toBe(2);
    expect((payload.links ?? []).length).toBe(1);
    expect(payload.selectionText).toBe("Selected line");
    expect(payload.metaDescription).toBe("description");
  });

  it("drops selection text when request does not include it", () => {
    const payload = toChromeExtractionInput(
      {
        url: "https://example.com",
        title: "Example",
        fullText: "Text",
        headings: [],
        links: [],
        selectionText: "Will be omitted",
      },
      false,
    );

    expect(payload.selectionText).toBe(undefined);
  });

  it("embeds includeSelectionText behavior in generated script", () => {
    const withSelection = buildChromeDocumentScript(true);
    const withoutSelection = buildChromeDocumentScript(false);

    expect(withSelection.includes("const selectionText = true")).toBe(true);
    expect(withoutSelection.includes("const selectionText = false")).toBe(true);
  });

  it("extracts context from a large JSON payload with default maxBuffer", async () => {
    const hugeText = "A".repeat(2 * 1024 * 1024);
    const fixturePath = join(tmpdir(), `context-grabber-chrome-large-${Date.now()}.json`);
    let fakeOsaBinary: string | undefined;
    const fixture = JSON.stringify({
      url: "https://example.com/large",
      title: "Large Document",
      fullText: hugeText,
      headings: [],
      links: [],
    });

    try {
      await writeFile(fixturePath, fixture, "utf8");
      fakeOsaBinary = await createFakeOsaScriptBinary(fixturePath);
      const payload = extractActiveTabContextFromChrome({
        includeSelectionText: false,
        osascriptBinary: fakeOsaBinary,
      });

      expect(payload.title).toBe("Large Document");
      expect(payload.fullText.length).toBe(hugeText.length);
    } finally {
      await rm(fixturePath, { force: true });
      if (fakeOsaBinary) {
        await rm(dirname(fakeOsaBinary), { recursive: true, force: true });
      }
    }
  });

  it("uses custom chromeAppName in AppleScript when provided", async () => {
    const argsOutputPath = join(tmpdir(), `context-grabber-osa-args-${Date.now()}.txt`);
    let spyBinary: string | undefined;

    try {
      spyBinary = await createAppleScriptSpyBinary(argsOutputPath);

      extractActiveTabContextFromChrome({
        includeSelectionText: false,
        osascriptBinary: spyBinary,
        chromeAppName: "Arc",
      });

      const capturedArgs = await readFile(argsOutputPath, "utf8");

      expect(capturedArgs.includes('tell application "Arc"')).toBe(true);
      expect(capturedArgs.includes("No Arc window is open.")).toBe(true);
      expect(capturedArgs.includes("Google Chrome")).toBe(false);
    } finally {
      await rm(argsOutputPath, { force: true });
      if (spyBinary) {
        await rm(dirname(spyBinary), { recursive: true, force: true });
      }
    }
  });

  it("defaults to Google Chrome when chromeAppName is not provided", async () => {
    const argsOutputPath = join(tmpdir(), `context-grabber-osa-args-default-${Date.now()}.txt`);
    let spyBinary: string | undefined;

    try {
      spyBinary = await createAppleScriptSpyBinary(argsOutputPath);

      extractActiveTabContextFromChrome({
        includeSelectionText: false,
        osascriptBinary: spyBinary,
      });

      const capturedArgs = await readFile(argsOutputPath, "utf8");

      expect(capturedArgs.includes('tell application "Google Chrome"')).toBe(true);
      expect(capturedArgs.includes("No Google Chrome window is open.")).toBe(true);
    } finally {
      await rm(argsOutputPath, { force: true });
      if (spyBinary) {
        await rm(dirname(spyBinary), { recursive: true, force: true });
      }
    }
  });
});
