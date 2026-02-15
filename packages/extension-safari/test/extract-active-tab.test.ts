import { describe, expect, it } from "bun:test";
import { chmod, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import {
  buildSafariDocumentScript,
  extractActiveTabContextFromSafari,
  toSafariExtractionInput,
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

const createWrappedJsonOsaScriptBinary = async (wrappedPayloadPath: string): Promise<string> => {
  const dir = await mkdtemp(join(tmpdir(), "context-grabber-safari-osa-wrapped-"));
  const binaryPath = join(dir, "wrapped-osascript.sh");

  await writeFile(
    binaryPath,
    ["#!/bin/sh", `cat "${wrappedPayloadPath}"`, "exit 0", ""].join("\n"),
    "utf8",
  );
  await chmod(binaryPath, 0o755);
  return binaryPath;
};

describe("safari active-tab extraction helpers", () => {
  it("sanitizes raw snapshots into Safari extraction payloads", () => {
    const payload = toSafariExtractionInput(
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
    const payload = toSafariExtractionInput(
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
    const withSelection = buildSafariDocumentScript(true);
    const withoutSelection = buildSafariDocumentScript(false);

    expect(withSelection.includes("const selectionText = true")).toBe(true);
    expect(withoutSelection.includes("const selectionText = false")).toBe(true);
  });

  it("extracts context from a large JSON payload with default maxBuffer", async () => {
    const hugeText = "A".repeat(2 * 1024 * 1024);
    const fixturePath = join(tmpdir(), `context-grabber-large-${Date.now()}.json`);
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
      const payload = extractActiveTabContextFromSafari({
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

  it("decodes wrapped JSON string payloads from osascript output", async () => {
    const wrappedPath = join(tmpdir(), `context-grabber-safari-wrapped-${Date.now()}.json`);
    let wrappedBinary: string | undefined;
    try {
      await writeFile(
        wrappedPath,
        JSON.stringify(
          JSON.stringify({
            url: "https://example.com/safari-wrapped",
            title: "Safari Wrapped JSON",
            fullText: "Wrapped output.",
            headings: [],
            links: [],
          }),
        ),
        "utf8",
      );
      wrappedBinary = await createWrappedJsonOsaScriptBinary(wrappedPath);
      const payload = extractActiveTabContextFromSafari({
        includeSelectionText: false,
        osascriptBinary: wrappedBinary,
      });

      expect(payload.title).toBe("Safari Wrapped JSON");
      expect(payload.url).toBe("https://example.com/safari-wrapped");
    } finally {
      await rm(wrappedPath, { force: true });
      if (wrappedBinary) {
        await rm(dirname(wrappedBinary), { recursive: true, force: true });
      }
    }
  });
});
