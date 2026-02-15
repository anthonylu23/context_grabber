import { describe, expect, it } from "bun:test";
import { buildDocumentScript } from "../src/document-script.js";

describe("shared document script builder", () => {
  it("embeds includeSelectionText=true in generated script", () => {
    const script = buildDocumentScript(true);
    expect(script.includes("const selectionText = true")).toBe(true);
  });

  it("embeds includeSelectionText=false in generated script", () => {
    const script = buildDocumentScript(false);
    expect(script.includes("const selectionText = false")).toBe(true);
  });

  it("produces a self-executing function", () => {
    const script = buildDocumentScript(true);
    expect(script.startsWith("(() => {")).toBe(true);
    expect(script.endsWith("})();")).toBe(true);
  });

  it("includes standard extraction fields", () => {
    const script = buildDocumentScript(true);
    expect(script.includes("document.location")).toBe(true);
    expect(script.includes("document.title")).toBe(true);
    expect(script.includes("document.body")).toBe(true);
    expect(script.includes("JSON.stringify")).toBe(true);
    expect(script.includes("headings")).toBe(true);
    expect(script.includes("links")).toBe(true);
  });

  it("does not serialize null selection as the string null", () => {
    const script = buildDocumentScript(true);
    const runScript = new Function("document", "window", `return ${script};`) as (
      document: Document,
      window: Window,
    ) => string;

    const serialized = runScript(
      {
        querySelector: () => null,
        querySelectorAll: () => [] as unknown as NodeListOf<Element>,
        location: { href: "https://example.com" } as Location,
        title: "Example",
        body: { innerText: "Body" } as HTMLElement,
        documentElement: { lang: "en" } as HTMLElement,
      } as unknown as Document,
      { getSelection: () => null } as unknown as Window,
    );
    const parsed = JSON.parse(serialized) as { selectionText?: string };

    expect(parsed.selectionText).toBe("");
    expect(parsed.selectionText === "null").toBe(false);
  });
});
