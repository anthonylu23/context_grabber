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
});
